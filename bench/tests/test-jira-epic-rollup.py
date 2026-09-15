import importlib.util
from pathlib import Path


PATH = Path(__file__).parents[1] / "lib" / "jira-epic-rollup.py"
SPEC = importlib.util.spec_from_file_location("jira_epic_rollup", PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)
evaluate = MODULE.evaluate


def test_active_child_starts_todo_epic():
    result = evaluate("execute_started", "new", [])
    assert result["target_status"] == "In Progress"


def test_active_child_does_not_regress_done_epic():
    assert evaluate("review_complete", "done", [])["action"] == "no-op"


def test_partial_settle_keeps_epic_in_progress():
    children = [
        {"key": "PROJ-1", "category": "done"},
        {"key": "PROJ-2", "category": "indeterminate"},
    ]
    result = evaluate("settled", "new", children)
    assert result["target_status"] == "In Progress"


def test_all_children_done_closes_epic():
    children = [
        {"key": "PROJ-1", "category": "done"},
        {"key": "PROJ-2", "category": "done"},
    ]
    result = evaluate("settled", "indeterminate", children)
    assert result["target_status"] == "Done"


def test_status_categories_are_case_insensitive():
    children = [{"key": "PROJ-1", "category": "DONE"}]
    result = evaluate("settled", "INDETERMINATE", children)
    assert result["target_status"] == "Done"


def test_unknown_child_prevents_closure():
    children = [
        {"key": "PROJ-1", "category": "done"},
        {"key": "PROJ-2", "category": "unknown"},
    ]
    result = evaluate("settled", "indeterminate", children)
    assert result["action"] == "no-op"
    assert result["unknown_children"] == ["PROJ-2"]


def test_unknown_child_still_starts_todo_epic():
    children = [
        {"key": "PROJ-1", "category": "done"},
        {"key": "PROJ-2", "category": "unknown"},
    ]
    result = evaluate("settled", "new", children)
    assert result["target_status"] == "In Progress"
    assert result["unknown_children"] == ["PROJ-2"]


def test_empty_child_set_prevents_closure():
    result = evaluate("settled", "indeterminate", [])
    assert result["action"] == "no-op"


def test_reopened_child_reopens_done_epic():
    result = evaluate("reopened", "done", [])
    assert result["target_status"] == "In Progress"
