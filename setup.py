from setuptools import setup, find_packages, Extension, dist
import numpy as np
import sys
import os

from distutils.command.install import install as DistutilsInstall

name = 'qgate'
version = '0.0.0'

pyver= [
    'Programming Language :: Python :: 3.5',
    'Programming Language :: Python :: 3.6',
    'Programming Language :: Python :: 3.7',
]

email = 'shin.morino@gmail.com'    
author='Shinya Morino'


classifiers=[
    'Operating System :: POSIX :: Linux',
    'Natural Language :: English',
    'License :: OSI Approved :: Apache Software License',
    'Topic :: Scientific/Engineering',
    'Topic :: Scientific/Engineering :: Artificial Intelligence',
]

url = 'https://github.com/shinmorino/qgate_sandbox/'

import os
os.system('make -C qgate/simulator/src clean cuda_obj')



npinclude = np.get_include()

ext_modules = []

# cpu_runtime
ext = Extension('qgate/simulator/cpuext',
                include_dirs = [npinclude],
                sources = ['qgate/simulator/src/CPURuntime.cpp',
                           'qgate/simulator/src/cpuext.cpp'],
                extra_compile_args = ['-std=c++11', '-fopenmp', '-Wno-format-security'])
ext_modules.append(ext)
ext = Extension('qgate/simulator/cudaext',
                include_dirs = [npinclude, '/usr/local/cuda/include'],
                sources = ['qgate/simulator/src/cudaext.cpp'],
                extra_objects = ['qgate/simulator/src/CUDARuntime.o'],
                libraries = ['cudart'],
                library_dirs = ['/usr/lib', '/usr/local/cuda/lib64'],
                extra_compile_args = ['-std=c++11', '-Wno-format-security'])
ext_modules.append(ext)
                    
setup(
    name=name,
    version=version,
    url=url,
    author=author,
    author_email=email,
    maintainer=author,
    maintainer_email=email,
    description='A collection of solvers for simulated quantum annealing.',
#    long_description=long_description,
    packages=find_packages(exclude=['tests']),
    install_requires=['numpy>=1.14'],
    keywords='Quantum gate simulator, OpenMP, GPU, CUDA',
    classifiers=classifiers,
    ext_modules=ext_modules
)
