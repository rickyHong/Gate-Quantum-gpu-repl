import qgate.model as model
import qgate.model.gate as gate
from .qubits import Qubits, Lane
from .value_store import ValueStore, ValueStoreSetter
from .operator_iterator import OperatorIterator
from .simple_executor import SimpleExecutor
from .runtime_operator import Translator, Observer
import numpy as np
import math


class Simulator :
    def __init__(self, defpkg, dtype) :
        self.defpkg = defpkg
        self.processor = defpkg.create_qubit_processor(dtype)
        self._qubits = Qubits(self.processor, dtype)
        self.translate = Translator(self._qubits)

    def set_circuits(self, circuits) :
        if len(circuits) == 0 :
            raise RuntimeError('empty circuits')
        self.circuits = circuits
        
    @property    
    def qubits(self) :
        return self._qubits
    
    @property
    def values(self) :
        return self._value_store

    def prepare(self, n_lanes_per_chunk = None, device_ids = []) :
        self.processor.reset() # release all internal objects
        self.executor = SimpleExecutor(self.processor)

        # merge all gates, and sort them.
        ops = []
        for circuit in self.circuits :
            ops += circuit.ops
        # FIXME: refine operator ordering
        self.ops = sorted(ops, key = lambda op : op.idx)

        for circuit in self.circuits :
            self._qubits.add_qregset(circuit.qregset, n_lanes_per_chunk, device_ids, self.defpkg)
        self._qubits.reset_all_qstates()
        
        # creating values store for references
        self._value_store = ValueStore()
        self._value_store.add(self.circuits.refset)
        
        self.op_iter = OperatorIterator(self.ops)

    def run_step(self) :
        op = self.op_iter.next()
        if op is None :
            self.executor.flush()
            return False

        if isinstance(op, model.IfClause) :
            if self._evaluate_if(op) :
                self.op_iter.prepend(op.clause)
        else :
            rop = self.translate(op)
            if isinstance(op, model.Measure) :
                value_setter = ValueStoreSetter(self._value_store, op.outref)
                # observer
                obs = self.executor.observer(value_setter)
                rop.set_observer(obs)
                
            self.executor.enqueue(rop)
            
        return True
    
    def run(self) :
        while self.run_step() :
            pass

    def terminate(self) :
        # release resources.
        self.circuits = None
        self._value_store = None
        self.ops = None
        self._qubits = None

    def _evaluate_if(self, op) :
        # synchronize
        values = self._value_store.get(op.refs)
        for value in values :
            if isinstance(value, Observer) :
                value.wait()

        packed_value = self._value_store.get_packed_value(op.refs)
        return packed_value == op.val
