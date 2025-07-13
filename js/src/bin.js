#!/usr/bin/env node

const { spawn } = require("child_process");
const { resolve } = require("path");

const child = spawn(
  "bash",
  [resolve(__dirname, "oogit.sh"), ...process.argv.slice(2)],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      NAME_OVERRIDE: "oogit",
    },
  }
);

child.on("error", (error) => {
  console.error(`[oogit] Error: ${error.message}`);
  process.exit(1);
});

child.on("close", (code) => {
  process.exit(code);
});
