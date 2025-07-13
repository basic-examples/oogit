#!/usr/bin/env node

import { Command } from "commander";
import { overwrite } from "./commands/overwrite";
import { extract } from "./commands/extract";
import { commit } from "./commands/commit";

const program = new Command();

program
  .name("oogit")
  .description("Version-control OOXML files using Git")
  .version("0.1.0");

program
  .command("overwrite")
  .argument("<ooxmlFile>", "Path to OOXML file")
  .argument("<gitRepo>", "Git repository URL")
  .argument("[repoPath]", "Path in repository")
  .argument("[branch]", "Branch to overwrite into")
  .option("-m, --message <message>")
  .option("-c, --commit-hash <hash>", "Expected latest commit hash")
  .action(overwrite);

program
  .command("extract")
  .argument("<ooxmlFile>", "Path to output OOXML file")
  .argument("<gitRepo>", "Git repository URL")
  .argument("[repoPath]", "Path in repository", "/")
  .argument("[branchOrCommit]", "Branch or commit to extract from")
  .option("-f", "Force overwrite if file exists")
  .action(extract);

program
  .command("commit")
  .argument("<ooxmlFile>", "Path to OOXML file (must have .oogit JSON config)")
  .action(commit);

program.parse();
