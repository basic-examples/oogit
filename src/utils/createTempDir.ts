import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const tempDirs = new Set<string>();

export function createTempDir(nameHint?: string): string {
  const base = tmpdir();
  const prefix = nameHint
    ? `oogit-${nameHint.replace(/[^a-zA-Z0-9-_]/g, "")}-`
    : "oogit-";
  const dir = mkdtempSync(join(base, prefix));
  tempDirs.add(dir);
  return dir;
}

function cleanTempDirs() {
  for (const dir of Array.from(tempDirs)) {
    if (existsSync(dir)) {
      try {
        rmSync(dir, { recursive: true, force: true });
      } catch {
        // ignore
      }
    }
  }
  tempDirs.clear();
}

process.on("exit", cleanTempDirs);
process.on("SIGINT", () => {
  cleanTempDirs();
  process.exit(1);
});
process.on("SIGTERM", () => {
  cleanTempDirs();
  process.exit(1);
});
process.on("uncaughtException", (err) => {
  console.error(err);
  cleanTempDirs();
  process.exit(1);
});
