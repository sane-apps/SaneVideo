#!/usr/bin/env python3
"""
Export all Swift code to a formatted PDF for code review.
Generates HTML with syntax highlighting, then converts to PDF.
"""

import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime

try:
    from pygments import highlight
    from pygments.lexers import SwiftLexer
    from pygments.formatters import HtmlFormatter
except ImportError:
    print("Installing Pygments...")
    subprocess.run([sys.executable, "-m", "pip", "install", "Pygments", "-q"])
    from pygments import highlight
    from pygments.lexers import SwiftLexer
    from pygments.formatters import HtmlFormatter


def collect_swift_files(root_dir: Path) -> list[tuple[Path, str]]:
    """Collect all Swift files, excluding build/test directories."""
    files = []
    exclude_dirs = {'build', '.build', 'DerivedData', 'Pods', '.git', 'SourcePackages'}

    for swift_file in sorted(root_dir.rglob("*.swift")):
        # Skip excluded directories
        if any(excluded in swift_file.parts for excluded in exclude_dirs):
            continue
        # Skip generated/dependency files
        if 'checkouts' in str(swift_file) or 'artifacts' in str(swift_file):
            continue

        rel_path = swift_file.relative_to(root_dir)
        try:
            content = swift_file.read_text(encoding='utf-8')
            files.append((rel_path, content))
        except Exception as e:
            print(f"Warning: Could not read {rel_path}: {e}")

    return files


def generate_toc(files: list[tuple[Path, str]]) -> str:
    """Generate table of contents HTML."""
    toc = ['<div class="toc"><h2>Table of Contents</h2><ul>']

    current_dir = None
    for rel_path, _ in files:
        parent = str(rel_path.parent)
        if parent != current_dir:
            if current_dir is not None:
                toc.append('</ul></li>')
            current_dir = parent
            toc.append(f'<li><strong>{parent}/</strong><ul>')

        anchor = str(rel_path).replace('/', '_').replace('.', '_')
        toc.append(f'<li><a href="#{anchor}">{rel_path.name}</a></li>')

    if current_dir is not None:
        toc.append('</ul></li>')

    toc.append('</ul></div>')
    return '\n'.join(toc)


def generate_html(files: list[tuple[Path, str]], project_name: str) -> str:
    """Generate complete HTML document with all code."""
    formatter = HtmlFormatter(
        linenos=True,
        cssclass='source',
        style='monokai',
        lineanchors='line',
        anchorlinenos=True
    )

    css = formatter.get_style_defs('.source')

    html_parts = [f'''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>{project_name} - Code Review</title>
    <style>
        @page {{
            size: letter;
            margin: 0.5in;
        }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            font-size: 11px;
            line-height: 1.4;
            color: #333;
            background: #fff;
            margin: 0;
            padding: 20px;
        }}
        .header {{
            text-align: center;
            border-bottom: 2px solid #333;
            padding-bottom: 20px;
            margin-bottom: 30px;
        }}
        .header h1 {{
            margin: 0;
            font-size: 28px;
        }}
        .header .subtitle {{
            color: #666;
            margin-top: 5px;
        }}
        .toc {{
            background: #f5f5f5;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 30px;
            page-break-after: always;
        }}
        .toc h2 {{
            margin-top: 0;
        }}
        .toc ul {{
            list-style: none;
            padding-left: 20px;
        }}
        .toc a {{
            color: #0066cc;
            text-decoration: none;
        }}
        .toc a:hover {{
            text-decoration: underline;
        }}
        .file-section {{
            page-break-before: always;
            margin-bottom: 40px;
        }}
        .file-section:first-of-type {{
            page-break-before: avoid;
        }}
        .file-header {{
            background: #2d2d2d;
            color: #fff;
            padding: 10px 15px;
            border-radius: 8px 8px 0 0;
            font-family: 'SF Mono', Monaco, monospace;
            font-size: 12px;
        }}
        .file-header .path {{
            opacity: 0.7;
        }}
        .file-header .filename {{
            font-weight: bold;
        }}
        .line-count {{
            float: right;
            opacity: 0.7;
        }}
        .source {{
            background: #272822;
            border-radius: 0 0 8px 8px;
            margin: 0;
            padding: 10px;
            overflow-x: auto;
        }}
        .source pre {{
            margin: 0;
            font-family: 'SF Mono', Monaco, 'Courier New', monospace;
            font-size: 10px;
            line-height: 1.5;
        }}
        .linenodiv {{
            border-right: 1px solid #555;
            padding-right: 10px;
            margin-right: 10px;
            color: #888;
            text-align: right;
            user-select: none;
        }}
        .stats {{
            margin-top: 30px;
            padding: 20px;
            background: #f0f0f0;
            border-radius: 8px;
        }}
        {css}
    </style>
</head>
<body>
    <div class="header">
        <h1>{project_name}</h1>
        <div class="subtitle">Code Review Export - {datetime.now().strftime('%B %d, %Y')}</div>
        <div class="subtitle">{len(files)} files | {sum(len(c.splitlines()) for _, c in files):,} lines</div>
    </div>
''']

    # Add table of contents
    html_parts.append(generate_toc(files))

    # Add each file
    lexer = SwiftLexer()
    for rel_path, content in files:
        anchor = str(rel_path).replace('/', '_').replace('.', '_')
        line_count = len(content.splitlines())
        parent = str(rel_path.parent)
        filename = rel_path.name

        highlighted = highlight(content, lexer, formatter)

        html_parts.append(f'''
    <div class="file-section" id="{anchor}">
        <div class="file-header">
            <span class="path">{parent}/</span><span class="filename">{filename}</span>
            <span class="line-count">{line_count} lines</span>
        </div>
        {highlighted}
    </div>
''')

    # Add statistics
    total_lines = sum(len(c.splitlines()) for _, c in files)
    html_parts.append(f'''
    <div class="stats">
        <h3>Summary</h3>
        <ul>
            <li><strong>Total Files:</strong> {len(files)}</li>
            <li><strong>Total Lines:</strong> {total_lines:,}</li>
            <li><strong>Generated:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</li>
        </ul>
    </div>
</body>
</html>
''')

    return ''.join(html_parts)


def html_to_pdf_macos(html_path: Path, pdf_path: Path) -> bool:
    """Convert HTML to PDF using macOS native tools."""
    # Try using cupsfilter (available on all Macs)
    try:
        result = subprocess.run(
            ['cupsfilter', '-o', 'fit-to-page', str(html_path)],
            capture_output=True,
            timeout=120
        )
        if result.returncode == 0:
            pdf_path.write_bytes(result.stdout)
            return True
    except Exception:
        pass

    # Fallback: use textutil + Preview via AppleScript
    try:
        # textutil can convert HTML but not directly to PDF
        # Use AppleScript to open in Safari and print to PDF
        script = f'''
        tell application "Safari"
            activate
            open POSIX file "{html_path}"
            delay 2
        end tell
        tell application "System Events"
            tell process "Safari"
                keystroke "p" using command down
                delay 1
                keystroke "p" using {{command down, shift down}}
                delay 1
                keystroke "g" using {{command down, shift down}}
                delay 0.5
                keystroke "{pdf_path}"
                delay 0.5
                keystroke return
                delay 2
            end tell
        end tell
        '''
        # This is complex, so we'll just leave HTML and instruct user
        return False
    except Exception:
        return False


def main():
    # Configuration
    project_root = Path("/Users/sj/SaneVideo")
    output_dir = Path.home() / "Desktop"
    project_name = "SaneVideo"

    print(f"📚 Exporting {project_name} code to PDF...")
    print(f"   Source: {project_root}")
    print(f"   Output: {output_dir}")

    # Collect files
    print("\n🔍 Collecting Swift files...")
    files = collect_swift_files(project_root)
    print(f"   Found {len(files)} Swift files")

    if not files:
        print("❌ No Swift files found!")
        return 1

    # Generate HTML
    print("\n🎨 Generating HTML with syntax highlighting...")
    html_content = generate_html(files, project_name)

    # Write HTML
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    html_path = output_dir / f"{project_name}_Code_Review_{timestamp}.html"
    html_path.write_text(html_content, encoding='utf-8')
    print(f"   ✅ HTML saved: {html_path}")

    # Try to convert to PDF
    pdf_path = output_dir / f"{project_name}_Code_Review_{timestamp}.pdf"
    print("\n📄 Converting to PDF...")

    # Check for wkhtmltopdf first (best quality)
    wkhtmltopdf = subprocess.run(['which', 'wkhtmltopdf'], capture_output=True)
    if wkhtmltopdf.returncode == 0:
        result = subprocess.run([
            'wkhtmltopdf',
            '--enable-local-file-access',
            '--page-size', 'Letter',
            '--margin-top', '10mm',
            '--margin-bottom', '10mm',
            '--margin-left', '10mm',
            '--margin-right', '10mm',
            '--encoding', 'UTF-8',
            str(html_path),
            str(pdf_path)
        ], capture_output=True, timeout=300)

        if result.returncode == 0:
            print(f"   ✅ PDF saved: {pdf_path}")
            # Clean up HTML if PDF succeeded
            html_path.unlink()
            print(f"\n🎉 Done! PDF exported to Desktop")
            return 0

    # If no PDF converter, provide instructions
    print(f"""
   ⚠️  Could not auto-convert to PDF (wkhtmltopdf not installed)

   📋 To create PDF manually:
      1. Open the HTML file: {html_path}
      2. In your browser, press Cmd+P
      3. Select "Save as PDF"
      4. Save to Desktop

   💡 Or install wkhtmltopdf for auto-conversion:
      brew install wkhtmltopdf
""")

    # Open HTML in default browser
    subprocess.run(['open', str(html_path)])
    print(f"\n✅ HTML opened in browser - use Cmd+P to print to PDF")

    return 0


if __name__ == "__main__":
    sys.exit(main())
