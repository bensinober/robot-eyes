## Requirements

Built with the new kid on the block - [Zig](https://ziglang.org/) - for speed, tolerance and curiosity.

Zig is a static low level C runner-up, still in its infancy but with great promise!

[OpenCV](https://opencv.org/) is the open source C++ computer vision spearhead, hence C++ wrappers had to be included. These are
blatantly borrowed and adjusted from [zigcv](https://github.com/ryoppippi/zigcv) which unfortunately just became stale. This again
loaned from [gocv](https://gocv.io/) which is a live and well library/wrapper for using OpenCV with the other language of preference - go.

Other technologies are in the machine learning sphere :

YOLO - you only look once - v8, which is the current model training format of choice

Autodistill - a self-labeling package on top of PyTorch, which is a python training and data modeling framework for neural networks
developed by Ultralytics and Torchvision.

## Prerequisites

You will, of course, [need Zig](https://ziglang.org/learn/getting-started/).

You will need OpenCV v4.8.0 installed with development headers. See install for linux below.

You will need a YOLO v8 model file, in ONNX format. I prepare mine with movie and autodistillation.
To be documented soon.

You will need Bun.js for API, web and bluetooth handling.

## Build and run

Main application

    zig build

    zig-out/bin/shell-game [camera id] [.onnx model file]


### Run with OpenCL (Intel GPU)

    OPENCV_DNN_OPENCL_ALLOW_ALL_DEVICES=1 zig-out/bin/shell-game [camera id] [.onnx model file]

## Web application and server (websocket)

Install bun (local user, on linux ~/.bun/bin/bun):

    curl -fsSL https://bun.sh/install | bash

Run server

    bun run server.js

### OpenCL

For better performance and detection on Intel GPU devices, OpenCL is recommended (Nvidia is better but a hog to install)

for info: https://support.zivid.com/en/latest/getting-started/software-installation/gpu/install-opencl-drivers-ubuntu.html

    mkdir neo && cd neo
    wget https://developer.download.nvidia.com/compute/cuda/12.2.1/local_installers/cuda-repo-ubuntu2204-12-2-local_12.2.1-535.86.10-1_amd64.deb
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-toolkit-12-config-common_12.2.140-1_all.deb
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-toolkit-12-2_12.2.1-1_amd64.deb
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-cudart-12-2_12.2.140-1_amd64.deb
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-cudart-dev-12-2_12.2.140-1_amd64.deb
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-nvcc-12-2_12.2.140-1_amd64.deb

    sudo apt install ./*.deb
    sudo apt install clinfo

    CC="zig cc" CXX="zig c++" cmake \
        -D CMAKE_BUILD_TYPE=RELEASE \
        -D WITH_IPP=OFF \
        -D WITH_OPENGL=OFF \
        -D WITH_QT=OFF \
        -D WITH_OPENVINO=OFF \
        -D WITH_OPENCL=ON \
        -D CMAKE_INSTALL_PREFIX=/usr/local \
        -D OPENCV_DNN_OPENCL=ON \
        -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib-4.8.0/modules/ \
        -D OPENCV_ENABLE_NONFREE=ON \
        -D OPENCV_GAPI_ONNX_MODEL_PATH=ON \
        -D WITH_JASPER=OFF \
        -D WITH_TBB=ON \
        -D BUILD_DOCS=OFF \
        -D BUILD_EXAMPLES=OFF \
        -D BUILD_TESTS=OFF \
        -D BUILD_PERF_TESTS=OFF \
        -D BUILD_opencv_java=NO \
        -D BUILD_opencv_python=NO \
        -D BUILD_opencv_python2=NO \
        -D BUILD_opencv_python3=NO \
        -D OPENCV_GENERATE_PKGCONFIG=ON \
        -D ENABLE_FAST_MATH=1 \
        ..


to run with opencl + dnn

    OPENCV_DNN_OPENCL_ALLOW_ALL_DEVICES=1 zig run

### OpenVino Inference backend (not working with zig)

    git clone https://github.com/openvinotoolkit/openvino.git
    cd openvino && mkdir build && cd build
    CC="zig cc" CXX="zig c++" CMAKE_CXX_FLAGS="" cmake -DCMAKE_BUILD_TYPE=Release ..
    make -j8

docker run -itu root:root  --rm --device /dev/dri:/dev/dri openvino/ubuntu22_dev:latest
/bin/bash -c "omz_downloader --name googlenet-v1 --precisions FP16 && omz_converter --name googlenet-v1 --precision FP16 && curl -O https://storage.openvinotoolkit.org/data/test_data/images/car_1.bmp && python3 samples/python/hello_classification/hello_classification.py public/googlenet-v1/FP16/googlenet-v1.xml car_1.bmp GPU"

## OpenCV install

    sudo apt-get install -y --no-install-recommends make cmake unzip git libv4l-dev \
    xz-utils curl ca-certificates libcurl4-openssl-dev libssl-dev libgtk2.0-dev libtbb-dev libavcodec-dev libavformat-dev libswscale-dev \
    libtbb2 libjpeg-dev libpng-dev libtiff-dev libdc1394-dev libblas-dev libopenblas-dev libeigen3-dev liblapack-dev libatlas-base-dev gfortran

On linux, the best approach is actually: download OpenCV source and build with Zig:

```
mkdir ~/opencv_build && cd ~/opencv_build
git clone https://github.com/opencv/opencv.git
git clone https://github.com/opencv/opencv_contrib.git

curl -Lo opencv.zip https://github.com/opencv/opencv/archive/refs/tags/$(OPENCV_VERSION).zip
unzip -q opencv.zip
curl -Lo opencv_contrib.zip https://github.com/opencv/opencv_contrib/archive/refs/tags/$(OPENCV_VERSION).zip
unzip -q opencv_contrib.zip
rm opencv.zip opencv_contrib.zip

cd opencv
mkdir -p build && cd build

CC="zig cc" CXX="zig c++" cmake \
    -D CMAKE_BUILD_TYPE=RELEASE \
    -D WITH_IPP=OFF \
    -D WITH_OPENGL=OFF \
    -D WITH_QT=OFF \
    -D WITH_OPENVINO=OFF \
    -D CMAKE_INSTALL_PREFIX=/usr/local \
    -D OPENCV_DNN_OPENCL=ON \
    -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules/ \
    -D OPENCV_ENABLE_NONFREE=ON \
    -D OPENCV_GAPI_ONNX_MODEL_PATH=ON \
    -D WITH_JASPER=OFF \
    -D WITH_TBB=ON \
    -D BUILD_DOCS=OFF \
    -D BUILD_EXAMPLES=OFF \
    -D BUILD_TESTS=OFF \
    -D BUILD_PERF_TESTS=OFF \
    -D BUILD_opencv_java=NO \
    -D BUILD_opencv_python=NO \
    -D BUILD_opencv_python2=NO \
    -D BUILD_opencv_python3=NO \
    -D OPENCV_GENERATE_PKGCONFIG=ON \
    ..
```

Optionally with Nvidia Cuda support:


    sudo apt install nvidia-cuda-toolkit

And cudadnn

    wget https://developer.nvidia.com/downloads/compute/cudnn/secure/8.9.3/local_installers/11.x/cudnn-local-repo-ubuntu2204-8.9.3.28_1.0-1_amd64.deb/
    sudo dpkg -i cudnn-local-repo-ubuntu2204-8.9.3.28_1.0-1_amd64.deb
    sudo cp /var/cudnn-local-repo-ubuntu2204-8.9.3.28/cudnn-local-7F7A158C-keyring.gpg /usr/share/keyrings/


CUDNN_TAR_FILE="cudnn-linux-x86_64-8.5.0.96_cuda11-archive.tar.xz"
wget https://developer.download.nvidia.com/compute/redist/cudnn/v8.5.0/local_installers/11.5/cudnn-linux-x86_64-8.5.0.96_cuda11-archive.tar.xz
tar -xzvf cudnn-linux-x86_64-8.5.0.96_cuda11-archive.tar.xz
sudo cp -P include/cudnn.h /usr/local/cuda-11.7/include
sudo cp -P lib/libcudnn* /usr/local/cuda-11.7/lib64/
sudo chmod a+r /usr/local/cuda-11.7/lib64/libcudnn*

tar -xqvf cudnn-linux-x86_64-8.9.5.29_cuda11-archive.tar.xz
sudo mkdir -p /usr/local/cuda/include
sudo cp cuda/include/cudnn*.h /usr/local/cuda/include
sudo mkdir -p /usr/local/cuda/lib64
sudo cp -P cuda/lib/libcudnn* /usr/local/cuda/lib
sudo chmod a+r /usr/local/cuda/include/cudnn*.h /usr/local/cuda/lib/libcudnn*


wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/libcudnn8_8.9.0.131-1+cuda11.8_amd64.deb
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/libcudnn8-dev_8.9.0.131-1+cuda11.8_amd64.deb
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/libnccl2_2.15.5-1+cuda11.8_amd64.deb
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/libnccl-dev_2.15.5-1+cuda11.8_amd64.deb
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/libnpp-11-8_11.8.0.86-1_amd64.deb
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/libnpp-dev-11-8_11.8.0.86-1_amd64.deb

```
export OPENCV_VERSION=4.8.0
mkdir /tmp/opencv && cd /tmp/opencv
curl -Lo opencv.zip https://github.com/opencv/opencv/archive/refs/tags/${OPENCV_VERSION}.zip
unzip -q opencv.zip
curl -Lo opencv_contrib.zip https://github.com/opencv/opencv_contrib/archive/refs/tags/${OPENCV_VERSION}.zip
unzip -q opencv_contrib.zip
cd opencv-${OPENCV_VERSION} && make build && cd build

CC="zig cc" CXX="zig c++" cmake \
    -D CMAKE_BUILD_TYPE=RELEASE \
    -D WITH_IPP=OFF \
    -D WITH_OPENGL=OFF \
    -D WITH_QT=OFF \
    -D WITH_OPENVINO=OFF \
    -D WITH_OPENCL=OFF \
    -D CMAKE_INSTALL_PREFIX=/usr/local \
    -D OPENCV_DNN_OPENCL=ON \
    -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib-4.8.0/modules/ \
    -D OPENCV_ENABLE_NONFREE=ON \
    -D OPENCV_GAPI_ONNX_MODEL_PATH=ON \
    -D WITH_JASPER=OFF \
    -D WITH_TBB=ON \
    -D BUILD_DOCS=OFF \
    -D BUILD_EXAMPLES=OFF \
    -D BUILD_TESTS=OFF \
    -D BUILD_PERF_TESTS=OFF \
    -D BUILD_opencv_java=NO \
    -D BUILD_opencv_python=NO \
    -D BUILD_opencv_python2=NO \
    -D BUILD_opencv_python3=NO \
    -D OPENCV_GENERATE_PKGCONFIG=ON \
    -D WITH_CUDA=ON \
    -D ENABLE_FAST_MATH=1 \
    -D CUDA_FAST_MATH=1 \
    -D WITH_CUBLAS=1 \
    -D CUDA_ARCH_PTX="" \
    -D CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda/ \
    -D BUILD_opencv_cudacodec=OFF \
    -D WITH_CUDNN=ON \
    -D OPENCV_DNN_CUDA=ON \
    -D CUDA_GENERATION=Auto \
    -D CUDNN_INCLUDE_DIR=/usr/include/x86_64-linux-gnu/ \
    -D CUDNN_LIBRARY=/usr/lib/x86_64-linux-gnu/ \
    ..
```

```
make -j8
make preinstall
sudo make install
sudo ldconfig
```

## Bluetooth


Bleno - for handling bluetooth BLE in backend (NOT USED - we use Web bluetooth API instead)
    sudo apt-get install libbluetooth-dev

    bun add bleno@npm:@abandonware/bleno

# if missing permissions for nodejs to advertise ble

    (sudo setcap cap_net_raw+eip $(eval readlink -f `which node`))

Device A4:06:E9:8E:00:0A HMSoft
Device 98:D3:C1:FD:B3:95 HC-05

pair animatronics device to be controlled
Linux: pair and connect with bluetoothctl

  $ bluetoothctl
  power on
  scan on
  trust <macaddr>
  pair <macaddr>
    enter PIN

you should now have /dev/rfcomm0

test with `screen /dev/rfcomm0 9600`
