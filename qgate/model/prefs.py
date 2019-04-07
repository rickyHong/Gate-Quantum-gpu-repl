
circuit_prep = 'circuit_prep'

#  1. one_static: Circuit are scanned prior to run, treating one big circuit, and have one state vector.
#  2. static: Circuit are scanned prior to run, seperating circuits, and have some states vector. (isolate_circuits)
#  3. dynamic: Circuit are successively scanned, Qregs are given as operator applied. (Cohere/Decohere)

dynamic = 'dynamic'
static = 'static'
one_static = 'one_static'
