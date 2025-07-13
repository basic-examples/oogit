import { cloneRepository } from "es-git";
import { unzipOoxmlTo } from "../utils/unzipOoxmlTo";
import { createTempDir } from "../utils/createTempDir";

export interface OverwriteOptions {
  message?: string;
  commitHash?: string;
}

export async function overwrite(
  ooxmlFile: string,
  gitRepo: string,
  repoPath = "/",
  branch: string | undefined,
  options: OverwriteOptions
) {
  const tempDir = createTempDir(ooxmlFile);
  const repo = await cloneRepository(gitRepo, tempDir, { branch });

  if (!repoPath.startsWith("/")) {
    repoPath = `/${repoPath}`;
  }

  if (options.commitHash) {
    const latestHashResult = repo
      .revwalk()
      .pushHead()
      [Symbol.iterator]()
      .next();
    const latestHash = latestHashResult.done ? null : latestHashResult.value;
    if (latestHash !== options.commitHash) {
      console.error(
        `[oogit] commit hash mismatch: ${latestHash} !== ${options.commitHash}`
      );
      process.exit(1);
    }
  }

  unzipOoxmlTo(ooxmlFile, `${tempDir}${repoPath}`);

  const index = repo.index();
  index.addAll(["*"]);
  index.write();

  const treeOid = index.writeTree();
  const tree = repo.getTree(treeOid);

  repo.commit(tree, options.message ?? `oogit overwrite: ${ooxmlFile}`, {
    updateRef: "HEAD",
    parents: [repo.head().target()!],
  });

  await repo.getRemote("origin").push();
}
