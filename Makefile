.PHONY: help create-conflict

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
