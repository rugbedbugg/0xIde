"""OCR package management without privileges, network access or package changes."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / 'shell/extensions/ocr/tree/assets/ocr/languages.py'
SPEC = importlib.util.spec_from_file_location('ocr_languages', SOURCE)
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


class LanguagePackages(unittest.TestCase):
    def setUp(self):
        self.installed = ['eng', 'afr']
        self.calls = []
        self.failure = None
        self.output = io.StringIO()
        self.enterContext(contextlib.redirect_stdout(self.output))
        self.enterContext(patch.object(helper.shutil, 'which', return_value='/usr/bin/tool'))
        self.enterContext(patch.object(helper, 'names', return_value={
            'eng': {'name': 'English', 'aliases': ['en']},
            'deu': {'name': 'German', 'aliases': ['de', 'ger']},
            'fra': {'name': 'French', 'aliases': ['fr', 'fre']},
        }))
        self.enterContext(patch.object(helper.subprocess, 'run', side_effect=self.run_command))

    def run_command(self, argv, **kwargs):
        self.calls.append(argv)
        if argv == [helper.PACMAN, '-Slq']:
            output = '\n'.join(['unrelated', 'tesseract-data-osd', 'tesseract-data-../bad'] +
                               [helper.PREFIX + c for c in ['eng', 'afr', 'deu', 'fra']])
        elif argv == [helper.PACMAN, '-Qq']:
            output = '\n'.join(['tesseract', 'tesseract-data-osd'] +
                               [helper.PREFIX + c for c in self.installed])
        else:
            self.assertEqual(argv[:2], [helper.PKEXEC, helper.PACMAN])
            self.assertNotIn('shell', kwargs)
            if self.failure:
                return subprocess.CompletedProcess(argv, *self.failure)
            code = argv[-1].removeprefix(helper.PREFIX)
            if argv[2] == '-S':
                self.installed.append(code)
            else:
                self.installed.remove(code)
            output = ''
        return subprocess.CompletedProcess(argv, 0, output, '')

    def mutations(self):
        return [c for c in self.calls if c[0] == helper.PKEXEC]

    def test_status_lists_only_language_packages(self):
        data = helper.catalogue()
        self.assertEqual(data['installed'], ['afr', 'eng'])
        self.assertEqual(data['installable'], ['afr', 'deu', 'eng', 'fra'])
        self.assertFalse(self.mutations())

    def test_install_by_name_is_one_package(self):
        self.assertEqual(helper.change('install', ' German '), 'Installed deu')
        self.assertEqual(self.mutations(), [[helper.PKEXEC, helper.PACMAN, '-S',
                         '--needed', '--noconfirm', '--', 'tesseract-data-deu']])
        self.assertEqual(json.loads(self.output.getvalue())['stage'], 'install')

    def test_names_and_aliases_resolve(self):
        languages = helper.catalogue()['available']
        for name in ['FRENCH', 'fra', 'fr', 'fre']:
            self.assertEqual(helper.resolve(name, languages), 'fra')

    def test_remove_cannot_cascade(self):
        self.assertEqual(helper.change('remove', 'afr'), 'Removed afr')
        self.assertEqual(self.mutations(), [[helper.PKEXEC, helper.PACMAN, '-R',
                         '--noconfirm', '--', 'tesseract-data-afr']])
        self.assertEqual(self.installed, ['eng'])

    def test_last_language_is_preserved(self):
        self.installed = ['eng']
        with self.assertRaisesRegex(ValueError, 'Keep at least one'):
            helper.change('remove', 'eng')
        self.assertFalse(self.mutations())

    def test_existing_install_needs_no_authentication(self):
        self.assertEqual(helper.change('install', 'English'), 'eng is already installed')
        self.assertFalse(self.mutations())

    def test_remove_absent_language_needs_no_authentication(self):
        with self.assertRaisesRegex(ValueError, 'not installed'):
            helper.change('remove', 'deu')
        self.assertFalse(self.mutations())

    def test_unknown_names_paths_options_and_orientation_are_rejected(self):
        for value in ['not a language', '../eng', '--noconfirm', 'eng; touch /tmp/x', 'osd', '']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                helper.change('install', value)
        self.assertFalse(self.mutations())

    def test_unknown_action_cannot_invoke_pacman(self):
        with self.assertRaises(ValueError):
            helper.change('upgrade', 'eng')
        self.assertEqual(self.calls, [])

    def test_cancelled_authentication_keeps_packages(self):
        self.failure = (126, '', '')
        with self.assertRaisesRegex(ValueError, 'cancelled'):
            helper.change('install', 'French')
        self.assertEqual(self.installed, ['eng', 'afr'])

    def test_authentication_failure_is_reported(self):
        self.failure = (127, '', 'Not authorized')
        with self.assertRaisesRegex(ValueError, 'approval failed'):
            helper.change('remove', 'afr')
        self.assertIn('afr', self.installed)

    def test_package_lock_or_dependency_error_is_reported(self):
        self.failure = (1, '', 'error: failed to init transaction (unable to lock database)')
        with self.assertRaisesRegex(ValueError, 'unable to lock database'):
            helper.change('install', 'deu')

    def test_missing_polkit_is_reported_without_mutation(self):
        helper.shutil.which.side_effect = lambda path: path if path == helper.PACMAN else None
        with self.assertRaisesRegex(ValueError, 'Install polkit'):
            helper.change('install', 'deu')
        self.assertFalse(self.mutations())

    def test_missing_pacman_is_reported(self):
        helper.shutil.which.return_value = None
        with self.assertRaisesRegex(ValueError, 'requires Arch Linux'):
            helper.catalogue()
        self.assertEqual(self.calls, [])

    def test_failed_package_query_is_reported(self):
        helper.subprocess.run.side_effect = None
        helper.subprocess.run.return_value = subprocess.CompletedProcess([], 1, '', 'database unavailable')
        with self.assertRaisesRegex(ValueError, 'database unavailable'):
            helper.catalogue()

    def test_success_requires_a_verified_package_change(self):
        with patch.object(helper, 'query', side_effect=[['tesseract-data-deu', 'tesseract-data-eng'],
                                                      ['tesseract-data-eng'], ['tesseract-data-eng']]):
            with self.assertRaisesRegex(ValueError, 'Could not verify'):
                helper.change('install', 'deu')


if __name__ == '__main__':
    unittest.main()
