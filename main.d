import std.stdio;

enum PREAMBLE =
"#include <gtk/gtk.h>\n" ~
"#define GETTEXT_PACKAGE \"gtk-snippets\"\n" ~
"#include <glib/gi18n-lib.h>\n";


struct Snippet {
  string filename;
  int lineNumber;
  string text;
}


void main(string[] args) {
	if (args.length < 2) {
		writeln("No input files given");
		return;
	}

	foreach (string filename; args[1..$]) {
		writeln("Checking ", filename, "...");

		if (!checkSnippets(filename)) {
			return;
		}
	}
}

import std.file;
import std.string;
import std.algorithm;
import std.range;

bool checkSnippets(string filename) {
  	string text = readText(filename);

  	auto lines = text.lineSplitter;

	int lineNumber = 0;
  	while (!lines.empty) {
		string line = lines.front;
		string snippetText;

		if (line.startsWith(" * |[") &&
		    line.indexOf("language=\"C\"") != -1) {
			Snippet snippet;
			snippet.lineNumber = lineNumber + 1;

			writeln("---------------------------------------------------");
			writeln("Snippet ", filename, ":", snippet.lineNumber, "...");

			for (;;) {
				lines.popFront;
				lineNumber ++;
				if (lines.empty)
					break;

				line = lines.front;
				if (line.startsWith(" * ]|")) {
					break;
				}
				// Comment lines start with a "*"
				auto asteriskIndex = line.indexOf("*");
				snippetText ~= line[asteriskIndex + 1..$].idup ~ "\n";
			}

			snippet.filename = filename;
			snippet.text = snippetText;

			//writeln ("");
			//writeln(snippet.text);
			//writeln ("");

			if (!compileTest(snippet)) {
				return false;
			}
		}


		if (!lines.empty) {
			lines.popFront();
			lineNumber ++;
		}
	}

	return true;
}

pure @safe string
getSnippetId(const ref Snippet s) {
	import std.conv: to;

	return s.filename ~ "_" ~ to!string(s.lineNumber);
}


import std.process;
auto spawn(string[] args) {
	return spawnProcess(args, std.stdio.stdin, stderr, stderr, null,
	                    Config.retainStderr | Config.retainStdout);
}

bool compileTest(const ref Snippet snippet) {
	// TODO(perf): We don't have to do this every time ...
	auto pipes = pipeProcess(["pkg-config", "--cflags", "--libs", "gtk+-4.0"],
	                         Redirect.stdout);
	if (wait(pipes.pid) != 0) {
		writeln("pkg-config failed :(");
		return false;
	}

	// We only have one line!
	string pkgConfigOutput = cast(string)pipes.stdout.byLine().front;
	string[] pkgs= pkgConfigOutput.split(' ');

	string snippetFilename = getSnippetId(snippet) ~ ".c";

	// First, we try to use the snippet inside a function
	string cText = PREAMBLE ~ "static void testThis() {\n";
	cText ~= snippet.text;
	cText ~= "\n}\n";
	cText ~= "int main(int argc, char **argv) { testThis(); return 0; }\n";

	// Race condition and inefficient but whatever
	if (exists(snippetFilename))
		remove(snippetFilename);
	toFile(cText, snippetFilename);


	string[] cmdLine = ["gcc"];
	cmdLine ~= pkgs;
	cmdLine ~= snippetFilename;

	// We first try to put the snippet into a function.
	// If that doesn't work, we assume the snippet contains a function itself
	// so we try it again without the surrounding function...
	auto gccProc1 = pipeProcess(cmdLine, Redirect.stdout | Redirect.stderr);

	if (wait(gccProc1.pid) != 0) {
		//write(gccProc1.stderr);

		// Now for the second time...
		string cText2 = PREAMBLE;
		cText2 ~= snippet.text;
		cText2 ~= "\n";
		cText2 ~= "int main(int argc, char **argv) { return 0; }";
		if (exists(snippetFilename))
			remove(snippetFilename);
		toFile(cText2, snippetFilename);

		auto gccProc2 = pipeProcess(cmdLine, Redirect.stdout | Redirect.stderr);

		if (wait(gccProc2.pid) != 0) {
			writeln("Snippet ", snippet.filename, ":", snippet.lineNumber, " Failed. Code: ");
			writeln("----------> IN FUNCTION");
			writeln(cText);
			foreach(line; gccProc1.stderr.byLine) {
				writeln(line);
			}

			// Unfortunately, I don't know how to print this properly...
			writeln("---------> FREESTANDING");
			writeln(cText2);
			foreach(line; gccProc2.stderr.byLine) {
				writeln(line);
			}
			return false;
		}
	}

	return true;
}

