#!/bin/bash

set -ex

sudo apt -q=2 update
pip3 install wheel
# Set local configuration
git config --global user.email "ci_notify@linaro.org"
git config --global user.name "Linaro CI"

cd ${WORKSPACE}

git clone --depth 1 "https://review.mlplatform.org/ml/ComputeLibrary"
git clone "https://review.mlplatform.org/ml/armnn"
git clone --depth 1 https://github.com/protocolbuffers/protobuf.git --branch v3.12.0 --single-branch
git clone --depth 1 https://github.com/tensorflow/tensorflow.git --branch r2.3 --single-branch
git clone --depth 1 https://github.com/google/flatbuffers.git --branch v1.12.0 --single-branch

sudo apt-get install -y libboost-all-dev
#swig 4.0
wget -q http://prdownloads.sourceforge.net/swig/swig-4.0.2.tar.gz
#export ONNX_ML=1
#git clone https://github.com/onnx/onnx.git
#unset ONNX_ML
#ComputeLibrary prebuilt
#wget -q https://github.com/ARM-software/ComputeLibrary/releases/download/v21.02/arm_compute-v21.02-bin-linux.tar.gz

if [ -n "$GERRIT_PROJECT" ] && [ $GERRIT_EVENT_TYPE == "patchset-created" ]; then
    cd armnn
    GERRIT_URL="http://${GERRIT_HOST}/${GERRIT_PROJECT}"
    if git pull ${GERRIT_URL} ${GERRIT_REFSPEC} | grep -q "Automatic merge failed"; then
	git reset --hard
        echo "Retrying to apply the patch with: git fetch && git checkout."
        if ! { git fetch ${GERRIT_URL} ${GERRIT_REFSPEC} | git checkout FETCH_HEAD; }; then
            git reset --hard
            echo "Error: *** Error patch merge failed"
            exit 1
        fi
    fi
fi

python3 --version

gcc --version

#build swig4.0 for PyArmNN
cd ${WORKSPACE}
tar -xf swig-4.0.2.tar.gz && rm -rf swig-4.0.2.tar.gz
cd ${WORKSPACE}/swig-4.0.2
./configure --prefix=${WORKSPACE}/swig-host --without-maximum-compile-warnings --without-pcre &&
make
make install


#cd ${WORKSPACE}
#tar xf arm_compute-v21.02-bin-linux.tar.gz
cd ${WORKSPACE}/ComputeLibrary
#git fetch "https://review.mlplatform.org/ml/ComputeLibrary" refs/changes/30/4230/5 && git cherry-pick FETCH_HEAD
#need to add for opencl=1 embed_kernels=1 and neon=1
#scons Werror=1 -u -j$(nproc) arch=arm64-v8a extra_cxx_flags="-fPIC" benchmark_tests=1 validation_tests=1 embed_kernels=1
scons Werror=1 -u -j$(nproc) arch=arm64-v8a benchmark_tests=0 debug=1 embed_kernels=1

#build Protobuf
cd ${WORKSPACE}/protobuf
git submodule update --init --recursive
./autogen.sh
./configure --prefix=${WORKSPACE}/protobuf-host
make -j$(nproc)
make install

#generate tensorflow protobuf library
cd ${WORKSPACE}/tensorflow
${WORKSPACE}/armnn/scripts/generate_tensorflow_protobuf.sh \
  ${WORKSPACE}/tensorflow-protobuf \
  ${WORKSPACE}/protobuf-host

#build google flatbuffer libraries
cd ${WORKSPACE}/flatbuffers
cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-fPIC"
make -j$(nproc)

#Build Onnx
#cd ${WORKSPACE}/onnx
#git checkout f612532843bd8e24efeab2815e45b436479cc9ab
#export LD_LIBRARY_PATH=${WORKSPACE}/protobuf-host/lib:$LD_LIBRARY_PATH
#${WORKSPACE}/protobuf-host/bin/protoc onnx/onnx.proto --proto_path=. --proto_path=${WORKSPACE}/protobuf-host/include --cpp_out ${WORKSPACE}/onnx

#Build Arm NN
cd ${WORKSPACE}/armnn
mkdir build
cd build
cmake .. \
  -DARMCOMPUTE_ROOT=${WORKSPACE}/ComputeLibrary \
  -DARMCOMPUTE_BUILD_DIR=${WORKSPACE}/ComputeLibrary/build \
  -DTF_GENERATED_SOURCES=${WORKSPACE}/tensorflow-protobuf \
  -DBUILD_TF_PARSER=1 \
  -DPROTOBUF_ROOT=${WORKSPACE}/protobuf-host \
  -DBUILD_TF_LITE_PARSER=1 \
  -DARMNNREF=1 \
  -DBUILD_TESTS=1 -DBUILD_UNIT_TESTS=1 \
  -DTF_LITE_GENERATED_PATH=${WORKSPACE}/tensorflow/tensorflow/lite/schema \
  -DFLATBUFFERS_ROOT=${WORKSPACE}/flatbuffers \
  -DFLATBUFFERS_LIBRARY=${WORKSPACE}/flatbuffers/libflatbuffers.a \
  -DSWIG_EXECUTABLE=${WORKSPACE}/swig-host/bin/swig \
  -DBUILD_PYTHON_SRC=1 \
  -DBUILD_PYTHON_WHL=1
make -j$(nproc)


cd ${WORKSPACE}
tar -cJf /tmp/armnn-full.tar.xz ${WORKSPACE}

rm -rf protobuf tensorflow
find ${WORKSPACE} -type f -name *.o -delete

mv armnn/include armnn/build
mv armnn/build .
mv armnn/python .
mv protobuf-host/lib/libprotobuf.so.* build
rm -rf armnn ComputeLibrary flatbuffers protobuf-host tensorflow-protobuf builders.sh
tar -cJf /tmp/armnn.tar.xz ${WORKSPACE}

mkdir ${WORKSPACE}/out
mv /tmp/armnn.tar.xz ${WORKSPACE}/out
mv /tmp/armnn-full.tar.xz ${WORKSPACE}/out
cd ${WORKSPACE}/out && sha256sum > SHA256SUMS.txt
