//          Copyright Mario Kröplin 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module main;

import std.array;
import std.stdio;

int main(string[] args)
{
    import std.getopt : defaultGetoptPrinter, getopt, GetOptException, GetoptResult;
    import std.path : baseName;

    GetoptResult result;
    try
    {
        result = getopt(args);
    }
    catch (GetOptException exception)
    {
        stderr.writeln("error: ", exception.msg);
        return 1;
    }
    if (result.helpWanted)
    {
        writefln("Usage: %s [option...] file...", baseName(args[0]));
        writeln("Reverse engineering of D source code into PlantUML classes.");
        writeln("If no files are specified, input is read from stdin.");
        defaultGetoptPrinter("Options:", result.options);
        return 0;
    }
    return process(args[1 .. $]);
}

int process(string[] names)
{
    import dparse.lexer : getTokensForParser, LexerConfig, StringBehavior, StringCache;
    import dparse.parser : parseModule;

    bool success = true;
    StringCache cache = StringCache(StringCache.defaultBucketCount);
    LexerConfig config;
    config.stringBehavior = StringBehavior.source;

    void outline(ubyte[] sourceCode, string name)
    {
        import dparse.rollback_allocator : RollbackAllocator;
        import outliner : Outliner;
        import std.typecons : scoped;

        config.fileName = name;
        auto tokens = getTokensForParser(sourceCode, config, &cache);
        RollbackAllocator allocator;
        auto module_ = parseModule(tokens, name, &allocator);
        auto visitor = scoped!Outliner(stdout, name);
        visitor.visit(module_);
    }

    if (names.empty)
    {
        outline(read(), "stdin");
    }
    else
    {
        string[] files;
        
        foreach (name; names)
        {
            import std.file : isDir, isFile;
            import std.path : absolutePath;
            
            // 转换为绝对路径
            auto absName = absolutePath(name);
            
            if (absName.isDir)
            {
                // 处理目录
                auto dirFiles = scanProjectDirectory(absName);
                if (dirFiles.empty)
                {
                    stderr.writeln("warning: No D source files found in directory: ", name);
                }
                else
                {
                    files ~= dirFiles;
                }
            }
            else if (absName.isFile)
            {
                // 处理文件
                files ~= absName;
            }
            else
            {
                stderr.writeln("error: Path does not exist: ", name);
                success = false;
            }
        }
        
        // 处理所有文件
        import std.file : FileException, read;
        
        foreach (file; files)
        {
            try
            {
                outline(cast(ubyte[]) read(file), file);
            }
            catch (FileException exception)
            {
                stderr.writeln("error: ", exception.msg);
                success = false;
            }
        }
    }
    return success ? 0 : 1;
}

string[] scanProjectDirectory(string directory)
{
    import std.file : exists, isDir;
    import std.path : buildPath;
    
    // 检查是否为 dub 项目
    bool isDubProject = exists(buildPath(directory, "dub.json")) ||
                        exists(buildPath(directory, "dub.sdl"));
    
    if (isDubProject)
    {
        return scanDubProject(directory);
    }
    else
    {
        // 对于非 dub 项目，直接扫描该目录
        return scanSourceDirectory(directory);
    }
}

string[] scanDubProject(string directory)
{
    // 暂时使用默认路径扫描，避免复杂的 dub API
    // TODO: 未来可以使用 dub 库的 API 来获取更精确的源文件路径
    return scanDefaultSourcePaths(directory);
}

string[] scanDefaultSourcePaths(string directory)
{
    import std.file : exists;
    import std.path : buildPath;
    
    string[] files;
    
    // 默认源文件路径
    string[] defaultPaths = ["source", "src"];
    
    foreach (path; defaultPaths)
    {
        auto fullPath = buildPath(directory, path);
        if (exists(fullPath))
        {
            files ~= scanSourceDirectory(fullPath);
        }
    }
    
    return files;
}

string[] scanSourceDirectory(string directory)
{
    import std.file : dirEntries, SpanMode, exists;
    
    string[] files;
    
    if (!exists(directory))
        return files;
    
    try
    {
        foreach (entry; dirEntries(directory, "*.d", SpanMode.depth))
        {
            files ~= entry.name;
        }
    }
    catch (Exception e)
    {
        stderr.writeln("warning: Failed to scan directory: ", directory, " - ", e.msg);
    }
    
    return files;
}

ubyte[] read()
{
    auto content = appender!(ubyte[])();
    ubyte[4096] buffer = void;
    while (!stdin.eof)
    {
        auto slice = stdin.rawRead(buffer);
        if (slice.empty || stdin.error)
            break;
        content.put(slice);
    }
    return content.data;
}
