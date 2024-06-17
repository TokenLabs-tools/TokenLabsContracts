import os
import re

def count_code_lines(file_path):
    with open(file_path, 'r', encoding='utf-8') as file:
        lines = file.readlines()

    code_lines = []
    in_multiline_comment = False

    for line in lines:
        stripped_line = line.strip()

        # Skip empty lines
        if not stripped_line:
            continue

        # Handle multiline comments
        if in_multiline_comment:
            if '*/' in stripped_line:
                in_multiline_comment = False
            continue

        if stripped_line.startswith('/*'):
            in_multiline_comment = True
            continue

        # Skip single line comments
        if stripped_line.startswith('//'):
            continue

        # Skip lines that contain only comments after code
        if '//' in stripped_line:
            stripped_line = stripped_line.split('//')[0].strip()

        code_lines.append(stripped_line)

    return len(code_lines)

def count_lines_in_directory(directory):
    total_lines = 0
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.sol'):
                file_path = os.path.join(root, file)
                lines_in_file = count_code_lines(file_path)
                total_lines += lines_in_file
                print(f"File: {file_path}, Lines of code: {lines_in_file}")
    return total_lines

if __name__ == "__main__":
    # Get the directory of the current script
    current_directory = os.path.dirname(os.path.abspath(__file__))
    total_lines = count_lines_in_directory(current_directory)
    print(f"Total lines of code: {total_lines}")
