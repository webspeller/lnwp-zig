export class LnwpApiClient {
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

  decodeFrame(request) {
    return this.post("/v1/frames/decode", request);
  }

  encodeFrame(request) {
    return this.post("/v1/frames/encode", request);
  }

  crc32c(request) {
    return this.post("/v1/checksums/crc32c", request);
  }

  snapshotHash(request) {
    return this.post("/v1/security/snapshot-hash", request);
  }

  batchMac(request) {
    return this.post("/v1/security/batch-mac", request);
  }

  get(path) {
    return this.request(path, { method: "GET" });
  }

  post(path, body) {
    return this.request(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  }

  async request(path, init) {
    const response = await fetch(`${this.baseUrl}${path}`, init);
    const text = await response.text();
    const json = text ? JSON.parse(text) : null;
    if (!response.ok) {
      throw new Error(json?.error ?? `LNWP API request failed with ${response.status}`);
    }
    return json;
  }
}
