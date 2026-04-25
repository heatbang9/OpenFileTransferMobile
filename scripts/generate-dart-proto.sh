#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/lib/generated"
PROTO_DIR="$ROOT_DIR/proto/proto"
PROTO_FILE="$PROTO_DIR/openfiletransfer/v1/transfer.proto"

mkdir -p "$OUT_DIR"

protoc \
  --dart_out=grpc:"$OUT_DIR" \
  -I"$PROTO_DIR" \
  "$PROTO_FILE"

echo "Dart gRPC 생성 완료: $OUT_DIR"

