from . import cpuext
import numpy as np
from .native_qubit_processor import NativeQubitProcessor
from .native_qubit_states import NativeQubitStates

def create_qubit_states(processor) :
    ptr = cpuext.qubit_states_new(processor.dtype)
    return NativeQubitStates(ptr, proc)

def create_qubit_processor(dtype) :
    return NativeQubitProcessor(dtype, cpuext.qubit_processor_new(dtype))
