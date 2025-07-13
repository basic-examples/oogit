import { build } from "esbuild";
import UnpluginTypia from "@ryoppippi/unplugin-typia/esbuild";

build({
  entryPoints: ["./src/bin.ts"],
  outfile: "./dist/bin.js",
  bundle: true,
  platform: "node",
  format: "esm",
  target: ["node18"],
  plugins: [UnpluginTypia({})],
  banner: {
    js: "#!/usr/bin/env node",
  },
});
