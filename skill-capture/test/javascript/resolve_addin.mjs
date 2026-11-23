import { pathToFileURL } from "node:url";
import { resolve as resolvePath } from "node:path";

export async function resolve(specifier, context, next) {
  if (specifier.startsWith("addin/")) {
    const file = resolvePath(process.cwd(), "app/javascript", `${specifier}.js`);
    return { url: pathToFileURL(file).href, shortCircuit: true };
  }
  return next(specifier, context);
}
