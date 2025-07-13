import AdmZip from "adm-zip";
import { rmdirSync } from "node:fs";

export function unzipOoxmlTo(ooxmlFile: string, targetPath: string) {
  rmdirSync(targetPath, { recursive: true });
  const zip = new AdmZip(ooxmlFile);
  zip.extractAllTo(targetPath, true);
}
