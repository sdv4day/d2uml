// Test dub library API
module test_dub_api;

import dub.package_;
import dub.project;
import std.stdio;

void main()
{
    // Try to load a package from current directory
    try
    {
        auto pkg = Package.load(".");
        writeln("Package name: ", pkg.name);
        writeln("Package path: ", pkg.path);
        writeln("Source paths: ", pkg.sourcePaths);
    }
    catch (Exception e)
    {
        writeln("Error: ", e.msg);
    }
}
