#!/bin/bash

set -ex

sudo apt -q=2 update
sudo apt-get -y install python3-dev virtualenv libboost-dev python3-setuptools libc6 libedit2 libstdc++6 libz3-4 zlib1g
pip3 install wheel
# Set local configuration
git config --global user.email "ci_notify@linaro.org"
git config --global user.name "Linaro CI"

cd ${WORKSPACE}

#wget http://ftp.br.debian.org/debian/pool/main/l/llvm-toolchain-11/libllvm11_11.0.1-2_arm64.deb
#sudo dpkg -i libllvm11_11.0.1-2_arm64.deb
sudo apt-get -y install llvm

git clone --recursive https://github.com/apache/tvm tvm

cd tvm && mkdir build

cp cmake/config.cmake build
sed -i -e 's/USE_MICRO OFF/USE_MICRO ON/' build/config.cmake
sed -i -e 's/USE_MICRO_STANDALONE_RUNTIME OFF/USE_MICRO_STANDALONE_RUNTIME ON/' build/config.cmake

cd build && cmake ..
make -j$(nproc)

cd ${WORKSPACE}/tvm && export TVM_HOME=`pwd`
export PYTHONPATH="${TVM_HOME}"/python:${PYTHONPATH}

cd ${WORKSPACE}/tvm && git clone https://github.com/google/googletest
cd googletest && mkdir build
cd build && cmake ..
make -j$(nproc)
sudo make install

cd ${WORKSPACE}/tvm
source tests/scripts/setup-pytest-env.sh
export LD_LIBRARY_PATH="lib:${LD_LIBRARY_PATH:-}"
export VTA_HW_PATH=`pwd`/3rdparty/vta-hw
export TVM_BIND_THREADS=0
export OMP_NUM_THREADS=1

make cpptest -j$(nproc)
make crttest

#cd ${WORKSPACE}/tvm
#./tests/scripts/task_cpp_unittest.sh

tar -cjf /tmp/tvm.tar.xz ${WORKSPACE} -C /home/buildslave/workspace/tvm-ci-build tvm


mkdir ${WORKSPACE}/out
mv /tmp/tvm.tar.xz ${WORKSPACE}/out
cd ${WORKSPACE}/out && sha256sum > SHA256SUMS.txt
