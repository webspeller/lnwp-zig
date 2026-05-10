export type DecodeFrameRequest = {
  hex: string;
};

export type EncodeFrameRequest = {
  opcode: string;
  flags?: number;
  body_hex?: string;
};

export type HexRequest = {
  hex: string;
};

export type SnapshotHashRequest = {
  key_hex: string;
  snapshot_seq: number;
  tree_root_fingerprint_hex: string;
};

export type BatchMacRequest = {
  key_hex: string;
  batch_seq: number;
  payload_hex: string;
};

export class LnwpApiClient {
  readonly baseUrl: string;

  constructor(baseUrl = "http://127.0.0.1:8080") {
    this.baseUrl = baseUrl.replace(/\/+$/, "");
  }

  health() {
    return this.get("/v1/health");
  }

  version() {
    return this.get("/v1/version");
  }

  opcodes() {
    return this.get("/v1/opcodes");
  }

  decodeFrame(request: DecodeFrameRequest) {
    return this.post("/v1/frames/decode", request);
  }

  encodeFrame(request: EncodeFrameRequest) {
    return this.post("/v1/frames/encode", request);
  }

  crc32c(request: HexRequest) {
    return this.post("/v1/checksums/crc32c", request);
  }

  snapshotHash(request: SnapshotHashRequest) {
    return this.post("/v1/security/snapshot-hash", request);
  }

  batchMac(request: BatchMacRequest) {
    return this.post("/v1/security/batch-mac", request);
  }

  private async get(path: string) {
    return this.request(path, { method: "GET" });
  }

  private async post(path: string, body: unknown) {
    return this.request(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  }

  private async request(path: string, init: RequestInit) {
    const response = await fetch(`${this.baseUrl}${path}`, init);
    const text = await response.text();
    const json = text ? JSON.parse(text) : null;
    if (!response.ok) {
      throw new Error(json?.error ?? `LNWP API request failed with ${response.status}`);
    }
    return json;
  }
}
