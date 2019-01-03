#include "DeviceGetStates.h"
#include "DeviceFunctors.cuh"
#include "DeviceParallel.h"
#include "Parallel.h"
#include <queue>

using namespace qgate_cuda;
using qgate::Qone;
using qgate::QstateIdx;
using qgate::QstateSize;


namespace {

template<class V> struct DeviceType;
template<> struct DeviceType<float> { typedef float Type; };
template<> struct DeviceType<double> { typedef double Type; };
template<> struct DeviceType<qgate::ComplexType<float>> { typedef DeviceComplexType<float> Type; };
template<> struct DeviceType<qgate::ComplexType<double>> { typedef DeviceComplexType<double> Type; };

}



template<class real>
DeviceGetStates<real>::DeviceGetStates(const qgate::QubitStatesList &qStatesList,
                                       CUDADeviceList &activeDevices) {

    activeDevices_ = activeDevices;
    int nQstates = (int)qStatesList.size();
    
    /* initialize list of qreg id list */
    IdList *idLists = new IdList[nQstates];
    DevicePtr *qStatesPtr = new DevicePtr[nQstates];
    memset(idLists, 0, sizeof(IdList) * nQstates);
    /* pack qreg id list */
    for (int qStatesIdx = 0; qStatesIdx < (int)nQstates; ++qStatesIdx) {
        const CUDAQubitStates<real> &cuQstates =
                static_cast<const CUDAQubitStates<real>&>(*qStatesList[qStatesIdx]);
        /* qregIds, qStatesPtr */
        const qgate::IdList &qregIds = cuQstates.getQregIdList();
        idLists[qStatesIdx].size = (int)qregIds.size();
        memcpy(idLists[qStatesIdx].id, qregIds.data(), sizeof(int) * qregIds.size());
        /* qstates ptr */
        qStatesPtr[qStatesIdx] = cuQstates.getDevicePtr();
    }

    /* create contexts */
    int nDevices = (int)activeDevices_.size();
    contexts_.resize(nDevices * nContextsPerDevice);
    for (int iDevice = 0; iDevice < nDevices; ++iDevice) {
        for (int iContext = 0; iContext < nContextsPerDevice; ++iContext) {
            int idx = iDevice * nContextsPerDevice + iContext;
            GetStatesContext &ctx = contexts_[idx];
            ctx.device = activeDevices_[iDevice];
            ctx.device->makeCurrent();
            ctx.dev.nQstates = nQstates;
            SimpleMemoryStore &dmemStore = ctx.device->tempDeviceMemory();
            ctx.dev.d_idLists = dmemStore.allocate<IdList>(ctx.dev.nQstates);
            throwOnError(cudaMemcpyAsync(ctx.dev.d_idLists, idLists,
                                         sizeof(IdList) * nQstates, cudaMemcpyDefault));
            ctx.dev.d_qStatesPtr = dmemStore.allocate<DevicePtr>(ctx.dev.nQstates);
            throwOnError(cudaMemcpyAsync(ctx.dev.d_qStatesPtr, qStatesPtr,
                                         sizeof(DevicePtr) * nQstates, cudaMemcpyDefault));
            throwOnError(cudaEventCreate(&ctx.event, cudaEventBlockingSync | cudaEventDisableTiming));
        }
    }
    for (int idx = 0; idx < (int)activeDevices_.size(); ++idx)
        activeDevices[idx]->synchronize();

    delete [] idLists;
    delete [] qStatesPtr;
}

template<class real>
DeviceGetStates<real>::~DeviceGetStates() {
    for (auto &it : contexts_)
        throwOnError(cudaEventDestroy(it.event));
    contexts_.clear();
}


template<class real>
void DeviceGetStates<real>::run(void *array, qgate::QstateIdx arrayOffset, qgate::MathOp op,
                                qgate::QstateIdx begin, qgate::QstateIdx end) {
    
    switch (op) {
    case qgate::mathOpNull: {
        Complex *cmpArray = static_cast<Complex*>(array);
        run(&cmpArray[arrayOffset], null<real>(), begin, end);
        break;
    }
    case qgate::mathOpProb: {
        real *vArray = static_cast<real*>(array);
        run(&vArray[arrayOffset], abs2<real>(), begin, end);
        break;
    }
    default:
        abort_("Unknown math op.");
    }
}


template<class real> template<class R, class F>
void DeviceGetStates<real>::run(R *values, const F &op,
                                qgate::QstateIdx begin, qgate::QstateIdx end) {
    typedef typename DeviceType<R>::Type DeviceR;
    
    size_t hMemCapacity = 1 << 30; /* just give a big value. */
    for (auto &ctx : contexts_) /* capacity of hostmem in all devices should be the same, but make sure to get the min value. */
        hMemCapacity = std::min(hMemCapacity, ctx.device->tempHostMemory().template remaining<DeviceR>());
    stride_ = (int)hMemCapacity / nContextsPerDevice;
    for (int idx = 0; idx < (int)contexts_.size(); ++idx) {
        GetStatesContext &ctx = contexts_[idx];
        ctx.dev.h_values = ctx.device->tempHostMemory().template allocate<DeviceR>(stride_);
    }
    
    begin_ = begin;
    pos_ = begin;
    end_ = end;

#if 0
    /* functor to allocate physical memory to touch pages. */
    auto touchPage = [=](int threadIdx, QstateIdx spanBegin, QstateIdx spanEnd) {
        int pageSizeInElm = 4096 / sizeof(R);
        for (QstateIdx idx = spanBegin; idx < spanEnd; idx += pageSizeInElm)
            values[idx] = 0;
    };
    qgate::Parallel().distribute(begin_, end_, touchPage);
#endif

    std::vector<std::queue<GetStatesContext*>> running;
    running.resize(activeDevices_.size());

    for (int idx = 0; idx < (int)contexts_.size(); ++idx) {
        GetStatesContext &ctx = contexts_[idx];
        if (!launch<R, F>(ctx, op))
            break;
        running[ctx.device->getDeviceNumber()].push(&contexts_[idx]);
    }

    auto queueRunner = [=, &running](int threadIdx) {
        while (!running[threadIdx].empty()) {
            GetStatesContext *ctx = running[threadIdx].front();
            running[threadIdx].pop();
            syncAndCopy(values, *ctx);
            if (launch<R, F>(*ctx, op))
                running[threadIdx].push(ctx);
        }
    };
    qgate::Parallel((int)activeDevices_.size()).run(queueRunner);

    for (auto &ctx : contexts_) {
        ctx.device->tempHostMemory().reset();  /* freeing host memory */
        ctx.device->tempDeviceMemory().reset();  /* freeing device memory */
    }
}

template<class real> template<class R, class F>
bool DeviceGetStates<real>::launch(GetStatesContext &ctx, const F &op) {

    if (pos_ == end_)
        return false;

    ctx.device->makeCurrent();
    ctx.dev.begin = pos_;
    ctx.dev.end = std::min(pos_ + stride_, end_);
    
    DeviceGetStatesContext devCtx = ctx.dev;
    QstateIdx offset = ctx.dev.begin;
    
    typedef typename DeviceType<R>::Type DeviceR;
    auto calcStatesFunc = [=]__device__(QstateIdx globalIdx) {                 
        DeviceR v = DeviceR(1.);
        for (int iQstates = 0; iQstates < devCtx.nQstates; ++iQstates) {
            /* getStateByGlobalIdx() */
            const IdList &d_qregIds = devCtx.d_idLists[iQstates];
            QstateIdx localIdx = 0;
            for (int lane = 0; lane < d_qregIds.size; ++lane) {
                int qregId = d_qregIds.id[lane]; 
                if ((Qone << qregId) & globalIdx)
                    localIdx |= Qone << lane;
            }
            const DeviceComplex &state = devCtx.d_qStatesPtr[iQstates][localIdx];
            v *= op(state);
        }
        ((DeviceR*)devCtx.h_values)[globalIdx - offset] = v;
    };
    transform(ctx.dev.begin, ctx.dev.end, calcStatesFunc);
    throwOnError(cudaEventRecord(ctx.event)); /* this works to flush driver queue like cudaStreamQuery(). */
    pos_ = ctx.dev.end;

    return true;
}

template<class real> template<class R>
void DeviceGetStates<real>::syncAndCopy(R *values, GetStatesContext &ctx) {
    throwOnError(cudaEventSynchronize(ctx.event));
    auto copyFunctor = [=](int threadIdx, QstateIdx spanBegin, QstateIdx spanEnd) {
        memcpy(&values[spanBegin - begin_], &((R*)ctx.dev.h_values)[spanBegin - ctx.dev.begin], sizeof(R) * (spanEnd - spanBegin));
    };
    int nWorkers = qgate::Parallel::getDefaultNumThreads() / (int)activeDevices_.size();
    qgate::Parallel().distribute(ctx.dev.begin, ctx.dev.end, copyFunctor, nWorkers);
}

template class DeviceGetStates<float>;
template class DeviceGetStates<double>;

