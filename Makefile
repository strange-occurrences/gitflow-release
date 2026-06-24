.PHONY: help create-conflict simulate-change update-submodule

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

create-conflict: ## Create a merge conflict between master and dev branches
	@echo "Creating merge conflict between master and dev branches..."
	@echo ""
	@echo "Step 1: Creating test file if it doesn't exist..."
	@test -f conflict-test.txt || echo "Original content" > conflict-test.txt
	@echo ""
	@echo "Step 2: Committing and pushing to master branch..."
	@git checkout master
	@git pull origin master || true
	@echo "Master branch content - this will conflict" > conflict-test.txt
	@git add conflict-test.txt
	@git commit -m "Create conflict on master branch"
	@git push origin master
	@echo ""
	@echo "Step 3: Committing and pushing conflicting change to dev branch..."
	@git checkout dev
	@git pull origin dev || true
	@echo "Dev branch content - this will conflict" > conflict-test.txt
	@git add conflict-test.txt
	@git commit -m "Create conflict on dev branch"
	@git push origin dev
	@echo ""
	@echo "✓ Conflict created successfully!"
	@echo ""
	@echo "To see the conflict, try merging dev into master:"
	@echo "  git checkout master"
	@echo "  git merge dev"
	@echo ""
	@echo "Or create a PR/merge request from dev to master"
	@echo ""
	@echo "Current branch: dev"

simulate-change: ## Simulate a change to a component (COMPONENT=<frontend|backend|infra|docs|bot> [MSG=...]); stages it, you commit & push
	@test -n "$(COMPONENT)" || { echo "Usage: make simulate-change COMPONENT=<frontend|backend|infra|docs|bot> [MSG=...]"; exit 1; }
	@test -d "$(COMPONENT)" || { echo "ERROR: component '$(COMPONENT)' not found"; exit 1; }
	@echo "- $$(date -u +%Y-%m-%dT%H:%M:%SZ) $(COMPONENT): $(if $(MSG),$(MSG),routine update)" >> $(COMPONENT)/CHANGELOG.md
	@git add $(COMPONENT)/CHANGELOG.md
	@echo "Staged change to $(COMPONENT)/CHANGELOG.md on branch $$(git rev-parse --abbrev-ref HEAD)."
	@echo "Commit and push to trigger ci-cd.yml, e.g.:"
	@echo "  git commit -m 'chore($(COMPONENT)): simulate change' && git push"

update-submodule: ## Move the subcomponent gitlink to the latest commit on its tracked branch (master); stages it, you commit & push
	@echo "Updating subcomponent (dummy-service) to the latest commit on master..."
	@echo ""
	@echo "Before:"
	@git submodule status
	@echo ""
	@git submodule update --remote subcomponent
	@git add subcomponent
	@echo ""
	@echo "After:"
	@git submodule status
	@echo ""
	@if git diff --cached --quiet -- subcomponent; then echo "subcomponent is already at the latest commit — nothing staged."; else echo "Staged gitlink bump for subcomponent on branch $$(git rev-parse --abbrev-ref HEAD)."; echo "Commit and push to update the reference, e.g.:"; echo "  git commit -m 'chore(submodule): bump subcomponent to latest' && git push"; fi
