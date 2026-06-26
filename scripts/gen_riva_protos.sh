#!/bin/bash
# Regenerates Swift code from the vendored NVIDIA Riva ASR protos.
#
# Generated output is committed (ParakeetKit/Riva/Generated) so normal builds do
# not need protoc. Re-run this only when the .proto files change or grpc-swift is
# upgraded. Requires `protoc` (brew install protobuf); builds the matching
# protoc-gen-swift / protoc-gen-grpc-swift from the resolved SPM checkouts so the
# generated code matches the linked runtime.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
PROTOROOT="ParakeetKit/Riva/protos"
OUT="$ROOT/ParakeetKit/Riva/Generated"

command -v protoc >/dev/null || { echo "protoc not found — brew install protobuf"; exit 1; }

echo "Building codegen plugins from resolved checkouts..."
swift build --package-path .build/checkouts/swift-protobuf -c release --product protoc-gen-swift
swift build --package-path .build/checkouts/grpc-swift-protobuf -c release --product protoc-gen-grpc-swift
GENSWIFT="$ROOT/.build/checkouts/swift-protobuf/.build/release/protoc-gen-swift"
GENGRPC="$ROOT/.build/checkouts/grpc-swift-protobuf/.build/release/protoc-gen-grpc-swift"

mkdir -p "$OUT"
cd "$PROTOROOT"
PROTOS=(riva/proto/riva_asr.proto riva/proto/riva_audio.proto riva/proto/riva_common.proto)

echo "Generating message types..."
protoc --plugin=protoc-gen-swift="$GENSWIFT" --proto_path=. \
  --swift_opt=Visibility=Internal --swift_out="$OUT" "${PROTOS[@]}"

echo "Generating gRPC client..."
protoc --plugin=protoc-gen-grpc-swift="$GENGRPC" --proto_path=. \
  --grpc-swift_opt=Visibility=Internal,Client=true,Server=false --grpc-swift_out="$OUT" "${PROTOS[@]}"

echo "Done. Generated into $OUT"
