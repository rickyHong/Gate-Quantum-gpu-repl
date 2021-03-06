import unittest
import qgate
import qgate.script as script

class SimulatorTestBase(unittest.TestCase) :
    
    def _run_sim(self, circuit, isolate_circuits = True) :
        pref = qgate.prefs.dynamic if isolate_circuits else qgate.prefs.one_static
        sim = self.create_simulator(circuit_prep = pref)
        sim.run(circuit)
        return sim

    def assertAlmostEqual(self, expected, actual) :
        unittest.TestCase.assertAlmostEqual(self, expected, actual, places = 5)



def create_py_simulator(self, **prefs) :
    return qgate.simulator.py(**prefs)

def create_cpu_simulator(self, **prefs) :
    return qgate.simulator.cpu(**prefs)

def create_cuda_simulator(self, **prefs) :
    return qgate.simulator.cuda(**prefs)


def createTestCases(module, class_name, base_class) :
    createPyTestCase(module, class_name, base_class)
    createCPUTestCase(module, class_name, base_class)
    createCUDATestCase(module, class_name, base_class)

def createPyTestCase(module, class_name, base_class) :
    py_class_name = class_name + 'Py'
    pytest_type = type(py_class_name, (base_class, ),
                       {"create_simulator":create_py_simulator})
    setattr(module, py_class_name, pytest_type)
    pytest_type.runtime = 'py'

def createCPUTestCase(module, class_name, base_class) :
    cpu_class_name = class_name + 'CPU'
    cputest_type = type(cpu_class_name, (base_class, ),
                        {"create_simulator":create_cpu_simulator})
    setattr(module, cpu_class_name, cputest_type)
    cputest_type.runtime = 'cpu'

def createCUDATestCase(module, class_name, base_class) :
    if hasattr(qgate.simulator, 'cudaruntime') :
        cuda_class_name = class_name + 'CUDA'
        cudatest_type = type(cuda_class_name, (base_class, ),
                            {"create_simulator":create_cuda_simulator})
        setattr(module, cuda_class_name, cudatest_type)
        cudatest_type.runtime = 'cuda'
        
