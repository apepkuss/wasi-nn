#!/bin/bash

set -e
if [ ! -d "/opt/intel/openvino" ]; then
    echo "Please install OpenVino"

else
    if [ -z $1 ]; then
        echo "Please specify as or rust to build"
    else
        BUILD_TYPE=$1
        BACKEND=$2
        PERF=$4
        LOOP_SIZE=$5
        export BACKEND=$BACKEND

        if [ -z "$3" ]; then MODEL="mobilenet_v2"; else MODEL=$3; fi
        if [ -z "$5" ]; then LOOP_SIZE="1"; else LOOP_SIZE=$5; fi
        export MODEL=$MODEL
        WASI_NN_DIR=$(dirname "$0" | xargs dirname)
        WASI_NN_DIR=$(realpath $WASI_NN_DIR)

        case $BUILD_TYPE in
            as)

                pushd $WASI_NN_DIR/assemblyscript
                npm install

                case $BACKEND in
                    openvino)
                        npm run openvino
                        ;;
                    tensorflow)
                        npm run tensorflow
                        ;;
                    *)
                        echo "Unknown backend, please enter 'openvino' or 'tensorflow'"
                        exit;
                        ;;
                esac
                ;;

            rust)
                echo "The first argument: $1"
                pushd $WASI_NN_DIR/rust/
                cargo build --release --target=wasm32-wasi
                mkdir -p $WASI_NN_DIR/rust/examples/classification-example/build
                RUST_BUILD_DIR=$(realpath $WASI_NN_DIR/rust/examples/classification-example/build/)
                cp -rn images $RUST_BUILD_DIR
                pushd examples/classification-example
                export MAPDIR="fixture"

                case $PERF in
                    perf)
                        case $LOOP_SIZE in
                            ''|*[!0-9]*)
                                echo "Loop size needs to be a number";
                                exit;
                                ;;
                            *)
                                export LOOP_SIZE=$LOOP_SIZE
                                ;;
                        esac
                    echo "RUNNING PERFORMANCE CHECKS"
                        cargo build --release --target=wasm32-wasi --features performance
                        ;;
                    *)
                        cargo build --release --target=wasm32-wasi
                        ;;
                esac

                cp target/wasm32-wasi/release/wasi-nn-example.wasm $RUST_BUILD_DIR

                case $BACKEND in
                    openvino)
                        echo "Using OpenVino"
                        source /opt/intel/openvino/bin/setupvars.sh
                        FIXTURE=https://github.com/intel/openvino-rs/raw/main/crates/openvino/tests/fixtures/mobilenet
                        cp models/$MODEL/model.bin $RUST_BUILD_DIR
                        cp models/$MODEL/model.xml $RUST_BUILD_DIR
                        cp models/$MODEL/tensor.desc $RUST_BUILD_DIR
                        ;;
                    tensorflow)
                        echo "Using Tensorflow"
                        cp src/saved_model.pb $RUST_BUILD_DIR
                        cp -r src/variables $RUST_BUILD_DIR
                        cp models/$MODEL/tensor.desc $RUST_BUILD_DIR
                        ;;
                    *)
                        echo "Unknown backend, please enter 'openvino' or 'tensorflow'"
                        exit;
                        ;;
                esac

                pushd build
                wasmtime run --mapdir fixture::$RUST_BUILD_DIR  wasi-nn-example.wasm --wasi-modules=experimental-wasi-nn
            ;;
            *)
                echo "Unknown build type $BUILD_TYPE"
            ;;
        esac

    fi
fi

