use anyhow::{Result, anyhow};
use clap::{Parser, Subcommand};
use git2::{Cred, FetchOptions, PushOptions, RemoteCallbacks, Repository, build::RepoBuilder};
use std::fs;
use std::fs::File;
use std::io::{Seek, Write};
use std::path::Path;
use zip::read::ZipArchive;
use zip::write::SimpleFileOptions;

#[derive(Parser, Debug)]
#[clap(name = "oogit", version = "0.2.2")]
pub struct Cli {
    /// Change working directory
    #[clap(short = 'C', long)]
    pub cwd: Option<String>,

    #[clap(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Initialize the repository and link to OOXML file
    Init {
        /// Specify commit message
        #[clap(short, long)]
        message: Option<String>,

        /// Overwrite existing file
        #[clap(short, long)]
        force: bool,

        /// OOXML file path
        ooxml_file: String,

        /// Git repository URL
        git_repo: String,

        /// Branch name
        branch: Option<String>,

        /// Path in repository
        path_in_repo: Option<String>,
    },

    /// Checkout repository content into OOXML file
    Checkout {
        /// Overwrite existing file
        #[clap(short, long)]
        force: bool,

        /// OOXML file path
        ooxml_file: String,

        /// Git repository URL
        git_repo: String,

        /// Branch name
        branch: Option<String>,

        /// Path in repository
        path_in_repo: Option<String>,
    },

    /// Commit changes from OOXML file into repository
    Commit {
        /// Specify commit message
        #[clap(short, long)]
        message: Option<String>,

        /// OOXML file path
        ooxml_file: String,
    },

    /// Update repository with changes from OOXML file
    Update {
        /// Specify commit message
        #[clap(short, long)]
        message: Option<String>,

        /// Overwrite existing file
        #[clap(short, long)]
        force: bool,

        /// OOXML file path
        ooxml_file: String,
    },

    /// Reset OOXML file to a specific commit or tag
    Reset {
        /// OOXML file path
        ooxml_file: String,

        /// Commit hash or tag (optional)
        tag_or_commit: Option<String>,
    },
}

fn zip<W: Write + Seek>(writer: W, dir: &std::path::Path) -> zip::result::ZipResult<()> {
    let mut zip = zip::ZipWriter::new(writer);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);

    for entry in walkdir::WalkDir::new(dir) {
        let entry = entry.unwrap();
        let path = entry.path();
        let name = path.strip_prefix(dir).unwrap();

        if path.is_file() {
            zip.start_file(name.to_string_lossy(), options)?;
            let mut f = std::fs::File::open(path)?;
            std::io::copy(&mut f, &mut zip)?;
        } else if !name.as_os_str().is_empty() {
            zip.add_directory(name.to_string_lossy(), options)?;
        }
    }

    zip.finish()?;
    Ok(())
}

fn unzip(zip_path: &str, output_dir: &std::path::Path) -> zip::result::ZipResult<()> {
    let file = File::open(zip_path)?;
    let mut archive = ZipArchive::new(file)?;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let out_path = output_dir.join(file.name());

        if file.is_dir() {
            std::fs::create_dir_all(&out_path)?;
        } else {
            if let Some(parent) = out_path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            let mut outfile = std::fs::File::create(&out_path)?;
            std::io::copy(&mut file, &mut outfile)?;
        }
    }
    Ok(())
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init {
            ooxml_file,
            git_repo,
            branch,
            path_in_repo,
            message,
            force,
        } => {
            let path_in_repo = path_in_repo.unwrap_or_default().to_string();
            let path_in_repo = if path_in_repo.starts_with("/") {
                path_in_repo
            } else {
                format!("/{}", path_in_repo)
            };
            oogit_init(
                &ooxml_file,
                &git_repo,
                branch.as_deref(),
                &path_in_repo,
                message.as_deref(),
                force,
            )?;
        }
        Commands::Checkout { .. } => {
            println!("Checkout");
        }
        Commands::Commit { .. } => {
            println!("Commit");
        }
        Commands::Update { .. } => {
            println!("Update");
        }
        Commands::Reset { .. } => {
            println!("Reset");
        }
    }
    Ok(())
}

pub fn oogit_init(
    ooxml_file: &str,
    repo_url: &str,
    branch: Option<&str>,
    path_in_repo: &str,
    commit_message: Option<&str>,
    force: bool,
) -> Result<()> {
    let meta_dir = format!("{}.oogit", ooxml_file);
    let repo_dir = format!("{}/repo", meta_dir);

    if Path::new(&meta_dir).exists() && !force {
        return Err(anyhow!(
            "{} already exists. Use --force to overwrite.",
            meta_dir
        ));
    }

    if Path::new(&repo_dir).exists() {
        fs::remove_dir_all(&repo_dir)?;
    }

    fs::create_dir_all(&repo_dir)?;

    let repo = if let Some(branch_name) = branch {
        match {
            let mut builder = RepoBuilder::new();
            if let Some(branch_name) = branch {
                builder.branch(branch_name);
            }
            builder.clone(repo_url, &repo_dir.as_ref())
        } {
            Ok(repo) => repo,
            Err(_) => {
                // Fallback orphan branch
                let repo = {
                    let mut builder = RepoBuilder::new();
                    if let Some(branch_name) = branch {
                        builder.branch(branch_name);
                    }
                    builder.clone(repo_url, &repo_dir.as_ref())
                }?;
                let refname = format!("refs/heads/{}", branch_name);
                repo.reference(
                    &refname,
                    repo.head()?.target().unwrap(),
                    true,
                    "orphan branch",
                )?;
                repo.set_head(&refname)?;
                repo
            }
        }
    } else {
        Repository::clone(repo_url, &repo_dir)?
    };

    let unzip_dir = format!("{}{}", repo_dir, path_in_repo);
    let unzip_dir = Path::new(&unzip_dir);
    unzip(ooxml_file, &unzip_dir)?;

    let mut index = repo.index()?;
    index.add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)?;
    index.write()?;

    if index.is_empty() {
        println!("Nothing to commit");
    } else {
        let oid = index.write_tree()?;
        let signature = repo.signature()?;
        let parent_commit = repo.head().ok().and_then(|h| h.peel_to_commit().ok());
        let tree = repo.find_tree(oid)?;

        if let Some(parent) = parent_commit {
            repo.commit(
                Some("HEAD"),
                &signature,
                &signature,
                commit_message.unwrap_or("oogit initial commit"),
                &tree,
                &[&parent],
            )?;
        } else {
            repo.commit(
                Some("HEAD"),
                &signature,
                &signature,
                commit_message.unwrap_or("oogit initial commit"),
                &tree,
                &[],
            )?;
        }
    }

    // Push
    let remotes = repo.remotes()?;
    let remote_name = remotes.get(0).ok_or_else(|| anyhow!("No remote found"))?;
    let mut remote = repo.find_remote(remote_name)?;
    let mut push_opts = PushOptions::new();

    let mut cb = RemoteCallbacks::new();
    cb.credentials(|_, _, _| Cred::default());
    push_opts.remote_callbacks(cb);

    let head_ref = repo.head()?;
    let branch_name = head_ref
        .shorthand()
        .ok_or_else(|| anyhow!("Branch name not found"))?;
    let refspec = format!("refs/heads/{}:refs/heads/{}", branch_name, branch_name); // TODO: define branch_name
    remote.push(&[refspec], Some(&mut push_opts))?;

    Ok(())
}
