#!/bin/bash

set -ex

sudo apt -q=2 update
pip3 install wheel
# Set local configuration
git config --global user.email "ci_notify@linaro.org"
git config --global user.name "Linaro CI"

cd ${WORKSPACE}

git clone --recursive https://github.com/apache/tvm tvm

cd tvm && mkdir build
export TVM_HOME=`pwd`
export PYTHONPATH="${TVM_HOME}"/python:${PYTHONPATH}

cp cmake/config.cmake build
sed -i -e 's/USE_MICRO OFF/USE_MICRO ON/' build/config.cmake
sed -i -e 's/USE_MICRO_STANDALONE_RUNTIME OFF/USE_MICRO_STANDALONE_RUNTIME ON/' build/config.cmake

cd build && cmake ..
make -j$(nproc)

cd ${WORKSPACE}/tvm && git clone https://github.com/google/googletest
cd googletest && mkdir build
cd build && cmake ..
make -j$(nproc)
sudo make install

tar -cjf /tmp/tvm.tar.xz ${WORKSPACE}/tvm


mkdir ${WORKSPACE}/out
mv /tmp/tvm.tar.xz ${WORKSPACE}/out
cd ${WORKSPACE}/out && sha256sum > SHA256SUMS.txt
