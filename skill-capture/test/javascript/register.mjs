// Resolve the importmap names ("addin/capture") to app/javascript/addin/*.js for Node's test runner.
import { register } from "node:module";
register("./resolve_addin.mjs", import.meta.url);
