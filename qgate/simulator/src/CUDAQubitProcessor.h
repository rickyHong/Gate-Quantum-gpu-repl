#pragma once

#include "Interfaces.h"
#include "DeviceTypes.h"

namespace qgate_cuda {

using qgate::Matrix2x2C64;
using qgate::QubitStates;
using qgate::MathOp;
using qgate::QstateIdx;
using qgate::QubitStatesList;

class CUDADevice;

template<class real>
class CUDAQubitProcessor : public qgate::QubitProcessor {
    typedef qgate::ComplexType<real> Complex;
    typedef DeviceComplexType<real> DeviceComplex;
public:
    CUDAQubitProcessor(CUDADevice &dev);
    ~CUDAQubitProcessor();

    virtual void prepare(qgate::QubitStates &qstates);
    
    virtual int measure(double randNum, QubitStates &qstates, int qregId) const;
    
    virtual void applyReset(QubitStates &qstates, int qregId) const;

    virtual void applyUnaryGate(const Matrix2x2C64 &mat, QubitStates &qstates, int qregId) const;

    virtual void applyControlGate(const Matrix2x2C64 &mat, QubitStates &qstates, int controlId, int targetId) const;

    virtual void getStates(void *array, QstateIdx arrayOffset,
                           MathOp op,
                           const QubitStatesList &qstatesList,
                           QstateIdx beginIdx, QstateIdx endIdx) const;
    
    
    template<class R, class F>
    void getStates(R *values, const F &func,
                   const QubitStatesList &qstatesList,
                   QstateIdx beginIdx, QstateIdx endIdx) const;

private:
    CUDADevice &dev_;
};
        
}
