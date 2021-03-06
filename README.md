# Freelancers' Mini-Tools

Mini-tools for empowering freelancers working in very constrained contexts
(shared hosting, etc).

In short: set of tools (bash scripts) providing simple-yet-powerful automation
to make on-going maintenance for Drupal websites quick and error-free, all this
while being able to leverage cheap (shared) hosting to keep infrastructure
costs very low.

Freelancers' Mini-Tools (fmt) is my humble attempt at bringing some of the
niceties of automation that are out of reach for low-budget projects in a form
that is simple enough to be used by freelancers or very small teams. The goal
is to empower developers on low-budget/very-constrained environments to make
the non-coding part of the work very streamlined and, hopefully, error-free.

# Why?

Being a freelancer brings lots of challenges with it, one of them being the
constant struggle to put time into the most impactful work (fixes,
improvements) rather than the seemingly low-impact (deploys, maintenance, etc).
This difficulty got me asking: is there a way to minimize the time spent on the
non-coding work while still doing it effectively?

The answer I came up with is to use some automation; but not the kind of
super-expensive, hard-to-maintain automation you normally see in medium to
high-budget projects; instead, a very-simple-yet-effective approach that should
target the hardest and most time-consuming parts. Freelancers' Mini-Tools is an
implementation that tries to actualize that idea.

# What?

Freelancers' Mini-Tools is just a set of scripts for managing PHP applications,
meant to provide both simple tooling or minimal automation for various
particular problems: deployment, easy tagging of releases in the git repo, etc.
Some of the tools are meant to be used for Drupal 8/9 projects, or include
accompanying scripts for that purpose; hopefully, the approach can be
successfully applied to other scenarios. Actual usage has been done only in a
Drupal 8 project, for now.

# How?

FMT assumes some constraints, simple enough to cover most use cases:

- The project codebase must be managed via git. Proper, basic, git knowledge is
  important for effective usage of the tools.
- To run a script, the environment must provide working installs of: git, bash,
  PHP. For script-specific requirements, check the script code.

Bash was chosen due to it being available pretty much everywhere. PHP was
allowed since the initial target system is Drupal 8, which also requires PHP.

# Usage

Each tool is stand-alone (or mostly); some of them complement each other very
nicely, like repo-management/fmt-tag-build.sh making it super-easy to tag a
commit for later deploying with deploy/fmt-deploy.sh. For drupal8, a couple
*EXPERIMENTAL* tools are provided to help in reducing inode usage
(fmt-build-drush-phar.sh, fmt-prune-drupal-code.sh); these are meant to be used
before committing code into the git repo.

Before using each script, make sure to read the usage instructions and
script-specific requirements included at the top (usually as a comment).

# Troubleshooting

Most shared hostings heavily limit the resources, which may cause various types
of errors.

For an error like 'fatal: unable to create threaded lstat: Resource temporarily
unavailable', you may try connecting (SSH) to the server and running:

```
git config --global core.preloadIndex false
```

If the error persists, try with these:

```
git config --global pack.threads "1"
git config --global pack.windowMemory "100m"
git config --global pack.packSizeLimit "100m"
```

For details, see:

- https://stackoverflow.com/a/33805069/6072846
- https://forums.cpanel.net/threads/unable-to-create-threaded-lstat.642257/

# Reference Material

- https://www.bounteous.com/insights/2020/03/11/automate-drupal-deployments/
- https://youtu.be/S9GLT4ssj2Q?t=155 (the whole explanation about CMI + how 
  to manage code vs. files vs. DB). The "Pantheon workflow" seems to be a good
  "blueprint" to follow in order to use fmt-deploy.sh effectively.

# TODO

- Provide some tutorial (written, video), showing how the various tools can be
  used for a Drupal 8 project.
- Review https://violinist.io/, check how easy/convenient it would be to add
  FMT support for it. Note: free plan allows for unlimited *public* repos.
