## Authoring commits

Prefer to squash the commits of your PR (*pull request*) and avoid adding commits like “Address review comments”. This creates a clearer git history, which doesn’t need to record the history of how the PR evolved.

We prefer to not squash commits when merging a PR because, especially for larger PRs, it sometimes makes sense to split the PR into multiple self-contained chunks of changes. For example, a PR might do a refactoring first before adding a new feature or fixing a bug. This separation is useful for two reasons:
- During review, the commits can be reviewed individually, making each review chunk smaller
- In case this PR introduced a bug that is identified later, it is possible to check if it resulted from the refactoring or the actual change, thereby making it easier find the lines that introduce the issue.

## Opening a PR

To submit a PR you don't need permissions on this repo, instead you can fork the repo and create a PR through your forked version.

For more information and instructions, read the GitHub docs on [forking a repo](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo).

Once you've pushed your branch, you should see an option on this repository's page to create a PR from a branch in your fork.

> [!TIP]
> If you are stuck, it’s encouraged to submit a PR that describes the issue you’re having, e.g. if there are tests that are failing, build failures you can’t resolve, or if you have architectural questions. We’re happy to work with you to resolve those issues.

## Opening a PR for Release Branch

See the [dedicated section][section] on the Swift project website.

[section]: https://www.swift.org/contributing/#release-branch-pull-requests

## Review and CI Testing

After you opened your PR, a maintainer will review it and test your changes in CI (*Continuous Integration*) by adding a `@swift-ci Please test` comment on the pull request. Once your PR is approved and CI has passed, the maintainer will merge your pull request.

Only contributors with [commit access](https://www.swift.org/contributing/#commit-access) are able to approve pull requests and trigger CI.
