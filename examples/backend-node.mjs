import { LnwpApiClient } from "../clients/javascript/lnwp-client.js";

const client = new LnwpApiClient("http://127.0.0.1:8080");

console.log(await client.version());
console.log(await client.decodeFrame({
  hex: "060000080000000000000001",
}));
