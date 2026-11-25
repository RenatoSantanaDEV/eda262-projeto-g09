from __future__ import annotations

import ast
import io
import re
import tokenize
import unittest
from pathlib import Path

PROJECT = Path(__file__).parents[2]
ROOTS = ("parte-2", "consultas", "verificacao")
SKIPPED = {".terraform", ".runtime", ".generated", "__pycache__"}


def code_files(*suffixes: str) -> list[Path]:
    files = []
    for root in ROOTS:
        for path in sorted((PROJECT / root).rglob("*")):
            if path.is_file() and path.suffix in suffixes and not SKIPPED.intersection(path.parts):
                files.append(path)
    return files


class CodeHygieneTests(unittest.TestCase):
    def test_python_has_no_comments_or_docstrings(self) -> None:
        for path in code_files(".py"):
            source = path.read_text(encoding="utf-8")
            with self.subTest(path=str(path.relative_to(PROJECT))):
                comments = [
                    token for token in tokenize.generate_tokens(io.StringIO(source).readline)
                    if token.type == tokenize.COMMENT and not (token.start[0] == 1 and token.string.startswith("#!"))
                ]
                self.assertEqual(comments, [])
                for node in ast.walk(ast.parse(source)):
                    if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
                        self.assertIsNone(ast.get_docstring(node))

    def test_shell_has_only_shebang_comment(self) -> None:
        for path in code_files(".sh"):
            lines = path.read_text(encoding="utf-8").splitlines()
            with self.subTest(path=str(path.relative_to(PROJECT))):
                self.assertTrue(lines[0].startswith("#!"))
                inline = [line for line in lines[1:] if line.lstrip().startswith("#")]
                self.assertEqual(inline, [])

    def test_terraform_and_sql_have_no_comments(self) -> None:
        for path in code_files(".tf", ".sql"):
            text = re.sub(r'"(?:[^"\\]|\\.)*"', '""', path.read_text(encoding="utf-8"))
            with self.subTest(path=str(path.relative_to(PROJECT))):
                self.assertNotRegex(text, r"(?m)^\s*(#|//|--)")
                self.assertNotIn("/*", text)


if __name__ == "__main__":
    unittest.main()
