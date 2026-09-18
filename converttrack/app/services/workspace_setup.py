from app.services.workspace_config import WorkspaceConfigStore


def setup_workspace(
    account_id: int,
    account_name: str = "",
    workspace_type: str = "custom",
    automation_mode: str = "classification",
    catalog_sources: list[str] | None = None,
) -> dict:
    store = WorkspaceConfigStore()
    return store.setup_workspace(
        account_id=account_id,
        account_name=account_name,
        workspace_type=workspace_type,
        automation_mode=automation_mode,
        catalog_sources=catalog_sources,
    )
