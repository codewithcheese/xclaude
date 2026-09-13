# GitHub Actions temporarily disabled

All workflow definitions are stored here instead of `.github/workflows`,
so GitHub Actions will not discover or run them once this change is pushed.
Existing runs are not cancelled by moving the definitions.

To restore them, move the `.yml` files back into `.github/workflows` and
commit and push the change. Local test commands remain available.
