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

    zig-out/bin/robot-eyes [camera id] [.onnx model file]


## System services

    sudo ln -s /home/plasma/robot-eyes/docs/robot-eyes-bunjs.service /etc/systemd/system/robot-eyes-bunjs.service
    sudo ln -s /home/plasma/robot-eyes/docs/robot-eyes.service /etc/systemd/system/robot-eyes.service

    sudo systemctl enable robot-eyes-bunjs.service
    sudo systemctl enable robot-eyes.service


### Run with OpenCL (Intel GPU)

    OPENCV_DNN_OPENCL_ALLOW_ALL_DEVICES=1 zig-out/bin/robot-eyes [camera id] [.caffee model file]

## Web application and server (websocket)

Install bun (local user, on linux ~/.bun/bin/bun):

    curl -fsSL https://bun.sh/install | bash

Run server

    bun run server.js

### OpenCL

For better performance and detection on Intel GPU devices, OpenCL is recommended (Nvidia is better but a hog to install)

for info: https://support.zivid.com/en/latest/getting-started/software-installation/gpu/install-opencl-drivers-ubuntu.html

    mkdir neo && cd neo
    wget https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.14828.8/intel-igc-core_1.0.14828.8_amd64.deb
    wget https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.14828.8/intel-igc-opencl_1.0.14828.8_amd64.deb
    wget https://github.com/intel/compute-runtime/releases/download/23.30.26918.9/intel-level-zero-gpu-dbgsym_1.3.26918.9_amd64.ddeb
    wget https://github.com/intel/compute-runtime/releases/download/23.30.26918.9/intel-level-zero-gpu_1.3.26918.9_amd64.deb
    wget https://github.com/intel/compute-runtime/releases/download/23.30.26918.9/intel-opencl-icd-dbgsym_23.30.26918.9_amd64.ddeb
    wget https://github.com/intel/compute-runtime/releases/download/23.30.26918.9/intel-opencl-icd_23.30.26918.9_amd64.deb
    wget https://github.com/intel/compute-runtime/releases/download/23.30.26918.9/libigdgmm12_22.3.0_amd64.deb

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
        -D OPENCV_EXTRA_MODULES_PATH=../opencv_contrib/modules/ \
        -D OPENCV_ENABLE_NONFREE=ON \
        -D OPENCV_GAPI_ONNX_MODEL_PATH=OFF \
        -D WITH_JASPER=OFF \
        -D WITH_TBB=ON \
        -D BUILD_DOCS=OFF \
        -D BUILD_EXAMPLES=OFF \
        -D BUILD_TESTS=OFF \
        -D BUILD_PERF_TESTS=OFF \
        -D BUILD_opencv_gapi=ON \
        -D BUILD_opencv_java=NO \
        -D BUILD_opencv_python=NO \
        -D BUILD_opencv_python2=NO \
        -D BUILD_opencv_python3=NO \
        -D OPENCV_GENERATE_PKGCONFIG=ON \
        -D ENABLE_FAST_MATH=1 \
        ../opencv

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

    sudo apt-get install -y --no-install-recommends make cmake unzip git libv4l-dev libimath-dev \
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
    -D OPENCV_GAPI_ONNX_MODEL_PATH=OFF \
    -D WITH_JASPER=OFF \
    -D WITH_TBB=ON \
    -D BUILD_DOCS=OFF \
    -D BUILD_EXAMPLES=OFF \
    -D BUILD_TESTS=OFF \
    -D BUILD_PERF_TESTS=OFF \
    -D BUILD_opencv_gapi=OFF \
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

    sudo apt install libdbus-1-dev libfmt-dev g++

    sudo apt-get install libbluetooth-dev

Prepare (make export.h)

    git clone https://github.com/OpenBluetoothToolbox/SimpleBLE
    cd SimpleBLE/simpleble
    cmake -B build_simpleble -DBUILD_SHARED_LIBS=TRUE .
    cd build_simpleble && make -j6
    sudo make install
    sudo ldconfig

## Conky

    sudo apt install conky

    mkdir -p .config/conky
```
cat <<'EOF' > ~/.config/conky/conky.conf
conky.config = {
    alignment = 'top_right',
    background = false,
    border_width = 1,
    cpu_avg_samples = 2,
    default_color = 'white',
    default_outline_color = 'white',
    default_shade_color = 'white',
    double_buffer = true,
    draw_borders = false,
    draw_graph_borders = true,
    draw_outline = false,
    draw_shades = false,
    extra_newline = false,
    font = 'DejaVu Sans Mono:size=12',
    gap_x = 60,
    gap_y = 60,
    minimum_height = 5,
    minimum_width = 5,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_ncurses = false,
    out_to_stderr = false,
    out_to_x = true,
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'desktop',
    show_graph_range = false,
    show_graph_scale = false,
    stippled_borders = 0,
    update_interval = 1.0,
    uppercase = false,
    use_spacer = 'none',
    use_xft = true,
};

conky.text = [[
${color grey}Host: $nodename
${color grey}Uptime:$color $uptime
${color grey}Frequency (in MHz):$color $freq
${color grey}Frequency (in GHz):$color $freq_g
${color grey}RAM Usage:$color $mem/$memmax - $memperc% ${membar 4}
${color grey}Swap Usage:$color $swap/$swapmax - $swapperc% ${swapbar 4}
${color grey}CPU Usage:$color $cpu% ${cpubar 4}
${color grey}Processes:$color $processes  ${color grey}Running:$color $running_processes
$hr
${color grey}File systems:
 / $color${fs_used /}/${fs_size /} ${fs_bar 6 /}
${color grey}Networking:
Up:$color ${upspeed} ${color grey} - Down:$color ${downspeed}
${color grey}NETWORK ${hr 2}
IP wifi: $alignr ${addr wlan0}
IP wan: $alignr ${execi 3600 curl ifconfig.me | tail }
IP lan: $alignr ${addr eth0}
$hr
DISKS ${hr 2}
/ $alignc ${fs_used /} / ${fs_size /} $alignr ${fs_used_perc /}%
${fs_bar /}
]];
EOF
```

## Opt a) Systemd servies

```
cat <<'EOF' | tee $HOME/conky.sh
#!/usr/bin/env bash

## Wait 20 seconds
sleep 5

## Run conky
conky
EOF
```
chmod +x conky.sh

conky:
```
cat <<'EOF' | sudo tee /etc/systemd/system/conky.service
#conky.service
[Unit]
Description=Start conky app
After=x11-autologin.service

[Service]
WorkingDirectory=/home/radxa
User=radxa
Group=radxa
Restart=always
RestartSec=3
ExecStart=/home/radxa/conky.sh
Environment=DISPLAY=:0

[Install]
WantedBy=multi-user.target
EOF
```

```
cat <<'EOF' | sudo tee /etc/systemd/system/robot-eyes-bunjs.service
#robot-eyes-bunjs.service
[Unit]
Description=Start robot-eyes bunjs server
After=network-online.target

[Service]
WorkingDirectory=/home/robot-eyz/robot-eyes
User=robot-eyz
Group=robot-eyz
Restart=always
ExecStart=/home/robot-eyz/.bun/bin/bun run server.js

[Install]
WantedBy=multi-user.target
EOF
```

```
cat <<'EOF' | sudo tee /etc/systemd/system/robot-eyes.service
#robot-eyes.service
[Unit]
Description=Start robot-eyes app
After=robot-eyes-bunjs.service

[Service]
WorkingDirectory=/home/radxa/robot-eyes
User=radxa
Group=radxa
Restart=always
#ExecStart=/home/radxa/robot-eyes/zig-out/bin/robot-eyes 0 models/MobileNetSSD_deploy.caffemodel
ExecStart=/home/radxa/robot-eyes/zig-out/bin/robot-eyes 0 models/yolo-fastest-1.1.weights
Environment=DISPLAY=:0
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket
Environment=OPENCV_DNN_OPENCL_ALLOW_ALL_DEVICES=1

[Install]
WantedBy=multi-user.target
EOF
```

    sudo systemctl daemon-reload
    sudo systemctl enable x11-autologin.service
    sudo systemctl enable robot-eyes-bunjs.service
    sudo systemctl enable robot-eyes.service
    sudo systemctl enable conky.service

## Opt b) .desktop autostart files

mkdir -p ~/.config/autostart

```
cat <<'EOF' > ~/.config/autostart/conky.desktop
[Desktop Entry]
Type=Application
Exec=sh -c "sleep 10; conky;"
Name=Conky
Comment=Autostart conky at login
EOF
```
```
cat <<'EOF' > ~/.config/autostart/robot-eyes.desktop
[Desktop Entry]
Type=Application
Path=/home/robot-eyz/robot-eyes
Exec=sh -c "OPENCV_DNN_OPENCL_ALLOW_ALL_DEVICES=1; sleep 1; cd robot-eyes; zig-out/bin/robot-eyes 4 0 models/yolo-fastest-1.1-xl.weights;"
Name=robot-eyes
Comment=Autostart robot-eyes at login
EOF
```