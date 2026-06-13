//          Copyright Mario Kröplin 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module outliner;

import dparse.ast;
import dparse.formatter;
import dparse.lexer;
import std.algorithm;
import std.array;
import std.conv;
import std.stdio;
import std.typecons;
import std.path;
import std.string;

class Outliner : ASTVisitor
{
    private File output;

    private string fileName;

    private Classifier classifier = Classifier.init;

    private string visibility = "+";

    private string[] modifiers;

    private Classifier[] classifiers = null;
    
    private Relation[] relations = null;
    
    private Package[] packages = null;

    alias visit = ASTVisitor.visit;

    public this(File output, string fileName)
    {
        this.output = output;
        this.fileName = fileName;
    }

    public override void visit(const AttributeDeclaration attributeDeclaration)
    {
        const attributes = protectionAttributes(attributeDeclaration.attribute);
        if (!attributes.empty)
            visibility = attributes.back.attribute.toVisibility;
    }

    public override void visit(const ClassDeclaration classDeclaration)
    {
        auto qualifiedName = classifier.qualifiedName;
        auto fullyQualifiedName = classifier.fullyQualifiedName;
        auto outliner = scoped!Outliner(output, fileName);
        outliner.classifier.type = "class";
        outliner.classifier.qualifiedName = qualifiedName ~ classDeclaration.name.text;
        outliner.classifier.fullyQualifiedName = fullyQualifiedName ~ classDeclaration.name.text;
        
        // 处理继承关系和接口实现
        if (classDeclaration.baseClassList !is null)
        {
            foreach (baseClass; classDeclaration.baseClassList.items)
            {
                auto app = appender!(char[]);
                app.format(baseClass.type2);
                string typeName = app.data.to!string;
                
                Relation rel;
                rel.from = outliner.classifier.fullyQualifiedName;
                rel.to = parseTypeName(typeName);
                
                // 判断是继承还是接口实现
                import std.ascii : isUpper;
                if (typeName.startsWith("I") && typeName.length > 1 && isUpper(typeName[1]))
                {
                    rel.type = RelationType.Realization;
                }
                else
                {
                    rel.type = RelationType.Inheritance;
                }
                outliner.relations ~= rel;
            }
        }
        
        // 处理类成员，提取关联关系
        classDeclaration.accept(outliner);
        
        // 分析字段类型，创建关联关系
        foreach (field; outliner.classifier.fields)
        {
            if (!field.type.empty && !isBasicType(field.type))
            {
                Relation rel;
                rel.from = outliner.classifier.fullyQualifiedName;
                rel.to = parseTypeName(stripArray(field.type));
                rel.type = RelationType.Association;
                
                // 判断多重性
                if (field.type.endsWith("[]"))
                {
                    rel.multiplicity = "*";
                }
                else
                {
                    rel.multiplicity = "1";
                }
                rel.label = field.name;
                outliner.relations ~= rel;
            }
        }
        
        classifiers ~= outliner.classifier ~ outliner.classifiers;
        relations ~= outliner.relations;
    }

    public override void visit(const Constructor constructor)
    {
        Method method;
        method.visibility = visibility;
        method.name = "this";
        auto app = appender!(char[]);
        app.format(constructor.parameters);
        method.parameters = app.data.to!string;
        classifier.methods ~= method;
    }

    public override void visit(const Declaration declaration)
    {
        string visibility = this.visibility;
        const attributes = protectionAttributes(declaration);
        if (!attributes.empty)
            this.visibility = attributes.back.attribute.toVisibility;
        this.modifiers = declaration.modifiers;
        super.visit(declaration);
        if (!attributes.empty)
            this.visibility = visibility;
    }

    public override void visit(const Destructor destructor)
    {
        Method method;
        method.visibility = visibility;
        method.name = "~this";
        classifier.methods ~= method;
    }

    public override void visit(const EnumDeclaration enumDeclaration)
    {
        auto qualifiedName = classifier.qualifiedName;
        auto fullyQualifiedName = classifier.fullyQualifiedName;
        auto outliner = scoped!Outliner(output, fileName);
        outliner.classifier.type = "enum";
        outliner.classifier.qualifiedName = qualifiedName ~ enumDeclaration.name.text;
        outliner.classifier.fullyQualifiedName = fullyQualifiedName ~ enumDeclaration.name.text;
        enumDeclaration.accept(outliner);
        classifiers ~= outliner.classifier ~ outliner.classifiers;
    }

    public override void visit(const EnumMember enumMember)
    {
        Field field;
        field.name = enumMember.name.text;
        classifier.fields ~= field;
    }

    public override void visit(const FunctionDeclaration functionDeclaration)
    {
        Method method;
        method.visibility = visibility;
        method.modifiers = modifiers.dup;
        method.name = functionDeclaration.name.text;
        if (functionDeclaration.hasAuto)
            method.modifiers ~= "auto";
        if (functionDeclaration.hasRef)
            method.modifiers ~= "ref";
        if (functionDeclaration.returnType !is null)
        {
            auto app = appender!(char[]);
            app.format(functionDeclaration.returnType);
            method.type = app.data.to!string;
        }
        auto app = appender!(char[]);
        app.format(functionDeclaration.parameters);
        method.parameters = app.data.to!string;
        
        // 提取文档注释
        if (functionDeclaration.comment !is null)
        {
            method.documentation = functionDeclaration.comment.strip;
        }
        
        classifier.methods ~= method;
    }

    public override void visit(const InterfaceDeclaration interfaceDeclaration)
    {
        auto qualifiedName = classifier.qualifiedName;
        auto fullyQualifiedName = classifier.fullyQualifiedName;
        auto outliner = scoped!Outliner(output, fileName);
        outliner.classifier.type = "interface";
        outliner.classifier.qualifiedName = qualifiedName ~ interfaceDeclaration.name.text;
        outliner.classifier.fullyQualifiedName = fullyQualifiedName ~ interfaceDeclaration.name.text;
        
        // 处理接口继承
        if (interfaceDeclaration.baseClassList !is null)
        {
            foreach (baseClass; interfaceDeclaration.baseClassList.items)
            {
                auto app = appender!(char[]);
                app.format(baseClass.type2);
                string baseName = app.data.to!string;
                Relation rel;
                rel.from = outliner.classifier.fullyQualifiedName;
                rel.to = parseTypeName(baseName);
                rel.type = RelationType.InterfaceInheritance;
                outliner.relations ~= rel;
            }
        }
        
        interfaceDeclaration.accept(outliner);
        classifiers ~= outliner.classifier ~ outliner.classifiers;
        relations ~= outliner.relations;
    }

    public override void visit(const Invariant invariant_)
    {
        // skip
    }

    public override void visit(const Module module_)
    {
        import std.string : toLower;

        if (module_.moduleDeclaration !is null)
        {
            classifier.fullyQualifiedName = module_.moduleDeclaration.moduleName.identifiers.map!"a.text".array;
        }
        else
        {
            classifier.fullyQualifiedName = [];
        }

        super.visit(module_);
        string name;
        if (module_.moduleDeclaration is null)
        {
            name = fileName.stripExtension.baseName;
        }
        else
        {
            name = module_.moduleDeclaration.moduleName.identifiers.back.text;
        }
        name = name.toLower;
        if (!classifier.fields.empty || !classifier.methods.empty)
        {
            classifier.type = "class";
            classifier.qualifiedName = [name];
            classifier.stereotype = "<<(M,gold)>>";
            classifier.write(output.lockingTextWriter);
        }
        
        // 按包分组输出类
        writeClassifiersByPackage();
        
        // 输出关系
        writeRelations();
    }

    public override void visit(const SharedStaticConstructor sharedStaticConstructor)
    {
        Method method;
        method.visibility = visibility;
        method.modifiers = ["{static}", "shared"];
        method.name = "this";
        classifier.methods ~= method;
    }

    public override void visit(const SharedStaticDestructor sharedStaticDestructor)
    {
        Method method;
        method.visibility = visibility;
        method.modifiers = ["{static}", "shared"];
        method.name = "~this";
        classifier.methods ~= method;
    }

    public override void visit(const StaticConstructor staticConstructor)
    {
        Method method;
        method.visibility = visibility;
        method.modifiers = ["{static}"];
        method.name = "this";
        classifier.methods ~= method;
    }

    public override void visit(const StaticDestructor staticDestructor)
    {
        Method method;
        method.visibility = visibility;
        method.modifiers = ["{static}"];
        method.name = "~this";
        classifier.methods ~= method;
    }

    public override void visit(const StructDeclaration structDeclaration)
    {
        auto qualifiedName = classifier.qualifiedName;
        auto fullyQualifiedName = classifier.fullyQualifiedName;
        auto outliner = scoped!Outliner(output, fileName);
        outliner.classifier.type = "class";
        outliner.classifier.qualifiedName = qualifiedName ~ structDeclaration.name.text;
        outliner.classifier.fullyQualifiedName = fullyQualifiedName ~ structDeclaration.name.text;
        outliner.classifier.stereotype = "<<(S,silver)>>";
        
        // 处理组合关系（结构体字段）
        structDeclaration.accept(outliner);
        
        // 分析字段类型，创建关联关系
        foreach (field; outliner.classifier.fields)
        {
            if (!field.type.empty)
            {
                Relation rel;
                rel.from = outliner.classifier.fullyQualifiedName;
                rel.to = parseTypeName(field.type);
                rel.type = RelationType.Association;
                rel.multiplicity = "*";
                rel.label = field.name;
                outliner.relations ~= rel;
            }
        }
        
        classifiers ~= outliner.classifier ~ outliner.classifiers;
        relations ~= outliner.relations;
    }

    public override void visit(const TemplateDeclaration templateDeclaration)
    {
        // 处理模板声明
        auto qualifiedName = classifier.qualifiedName;
        auto fullyQualifiedName = classifier.fullyQualifiedName;
        auto outliner = scoped!Outliner(output, fileName);
        
        outliner.classifier.type = "class";
        outliner.classifier.qualifiedName = qualifiedName ~ templateDeclaration.name.text;
        outliner.classifier.fullyQualifiedName = fullyQualifiedName ~ templateDeclaration.name.text;
        outliner.classifier.stereotype = "<<(T,orange)>>";
        
        // 添加模板参数信息
        if (templateDeclaration.templateParameters !is null)
        {
            string templateParams = "{";
            auto app = appender!(char[]);
            app.format(templateDeclaration.templateParameters);
            templateParams ~= app.data.to!string;
            templateParams ~= "}";
            outliner.classifier.templateParams = templateParams;
        }
        
        templateDeclaration.accept(outliner);
        classifiers ~= outliner.classifier ~ outliner.classifiers;
    }

    public override void visit(const Unittest unittest_)
    {
        // skip
    }

    public override void visit(const VariableDeclaration variableDeclaration)
    {
        Field field;
        field.visibility = visibility;
        field.modifiers = modifiers.dup;
        if (variableDeclaration.type !is null)
        {
            auto app = appender!(char[]);
            app.format(variableDeclaration.type);
            field.type = app.data.to!string;
        }
        
        // 提取文档注释
        if (variableDeclaration.comment !is null)
        {
            field.documentation = variableDeclaration.comment.strip;
        }
        
        foreach (declarator; variableDeclaration.declarators)
        {
            field.name = declarator.name.text;
            classifier.fields ~= field;
        }
    }
    
    private string[] parseTypeName(string typeName)
    {
        string[] parts = typeName.split(".");
        return parts;
    }
    
    private bool isBasicType(string typeName)
    {
        string[] basicTypes = ["void", "bool", "byte", "ubyte", "short", "ushort", 
                              "int", "uint", "long", "ulong", "float", "double", 
                              "real", "char", "wchar", "dchar", "string", "immutable",
                              "const", "shared"];
        string baseType = stripArray(typeName);
        return basicTypes.canFind(baseType);
    }
    
    private string stripArray(string typeName)
    {
        if (typeName.endsWith("[]"))
        {
            return typeName[0..$-2].strip;
        }
        return typeName;
    }
    
    private void writeClassifiersByPackage()
    {
        // 按包分组
        string[string] classifiersByPackage;
        
        foreach (c; classifiers)
        {
            string packageName = c.packageName;
            classifiersByPackage[packageName] ~= c.toString();
        }
        
        foreach (packageName, content; classifiersByPackage)
        {
            if (!packageName.empty)
            {
                output.writefln("package %s {", packageName);
                output.writeln(content);
                output.writeln("}");
            }
            else
            {
                output.writeln(content);
            }
        }
    }
    
    private void writeRelations()
    {
        foreach (rel; relations)
        {
            string fromName = rel.from.join(".");
            string toName = rel.to.join(".");
            
            final switch (rel.type)
            {
                case RelationType.Inheritance:
                    output.writefln("%s --|> %s", fromName, toName);
                    break;
                case RelationType.Realization:
                    output.writefln("%s ..|> %s", fromName, toName);
                    break;
                case RelationType.InterfaceInheritance:
                    output.writefln("%s --|> %s : <<interface>>", fromName, toName);
                    break;
                case RelationType.Association:
                    string label = rel.label.empty ? "" : " : " ~ rel.label;
                    string multiplicity = rel.multiplicity.empty ? "" : "\"" ~ rel.multiplicity ~ "\" ";
                    output.writefln("%s %s--> %s%s", fromName, multiplicity, toName, label);
                    break;
                case RelationType.Composition:
                    output.writefln("%s *-- %s", fromName, toName);
                    break;
                case RelationType.Aggregation:
                    output.writefln("%s o-- %s", fromName, toName);
                    break;
            }
        }
    }
}

struct Classifier
{
    const string indent = "  ";

    string type;

    string[] qualifiedName = null;

    const(string)[] fullyQualifiedName = null;

    string stereotype;
    
    string templateParams;

    Field[] fields;

    Method[] methods;
    
    string documentation;
    
    string packageName() const
    {
        if (fullyQualifiedName.length > 1)
            return fullyQualifiedName[0..$-1].join(".");
        return "";
    }

    void write(Sink)(Sink sink) const
    {
        sink.put(type);
        sink.put(' ');
        foreach (index, name; qualifiedName)
        {
            if (index > 0)
                sink.put('.');
            sink.put(name);
        }
        
        // 添加模板参数
        if (!templateParams.empty)
        {
            sink.put(' ');
            sink.put(templateParams);
        }
        
        sink.put(' ');
        if (!stereotype.empty)
        {
            sink.put(stereotype);
            sink.put(' ');
        }
        sink.put("$generated");
        sink.put(' ');
        sink.put("$");
        foreach (index, name; fullyQualifiedName)
        {
            if (index > 0)
                sink.put('.');
            sink.put(name);
        }
        sink.put(' ');
        sink.put("{");
        sink.put('\n');
        
        // 输出文档注释
        if (!documentation.empty)
        {
            sink.put(indent);
            sink.put("/** ");
            sink.put(documentation);
            sink.put(" */");
            sink.put('\n');
        }
        
        foreach (field; fields)
        {
            sink.put(indent);
            field.write(sink);
            sink.put('\n');
        }
        foreach (method; methods)
        {
            sink.put(indent);
            method.write(sink);
            sink.put('\n');
        }
        sink.put("}");
        sink.put('\n');
    }
    
    string toString() const
    {
        import std.array : appender;
        auto app = appender!(char[]);
        write(app);
        return app.data.to!string;
    }
}

struct Field
{
    string visibility;

    string[] modifiers;

    string type;

    string name;
    
    string documentation;

    void write(Sink)(Sink sink) const
    {
        // 输出文档注释
        if (!documentation.empty)
        {
            sink.put("/** ");
            sink.put(documentation);
            sink.put(" */ ");
        }
        
        sink.put("{field} ");
        sink.put(visibility);
        foreach (modifier; modifiers)
        {
            sink.put(modifier);
            sink.put(' ');
        }
        if (!type.empty)
        {
            sink.put(type);
            sink.put(' ');
        }
        sink.put(name);
    }
}

struct Method
{
    string visibility;

    string[] modifiers;

    string type;

    string name;

    string parameters = "()";
    
    string documentation;

    void write(Sink)(Sink sink) const
    {
        // 输出文档注释
        if (!documentation.empty)
        {
            sink.put("/** ");
            sink.put(documentation);
            sink.put(" */ ");
        }
        
        sink.put(visibility);
        foreach (modifier; modifiers)
        {
            sink.put(modifier);
            sink.put(' ');
        }
        if (!type.empty)
        {
            sink.put(type);
            sink.put(' ');
        }
        sink.put(name);
        sink.put(escape(parameters));
    }
}

enum RelationType
{
    Inheritance,
    Realization,
    InterfaceInheritance,
    Association,
    Composition,
    Aggregation
}

struct Relation
{
    const(string)[] from;
    const(string)[] to;
    RelationType type;
    string label;
    string multiplicity;
}

struct Package
{
    string name;
    Classifier[] classifiers;
}

private string escape(string source) pure
{
    return source.replace(`\`, `\\`);
}

private const(Attribute[]) protectionAttributes(const Declaration declaration) pure
{
    const(Attribute)[] attributes = null;
    foreach (attribute; declaration.attributes)
        attributes ~= protectionAttributes(attribute);
    return attributes;
}

private const(Attribute[]) protectionAttributes(const Attribute attribute) pure
{
    return (attribute.attribute.type.isProtection) ? [attribute] : null;
}

private string toVisibility(const Token token) pure
in (token.type.isProtection)
{
    switch (token.type)
    {
    case tok!"package":
        return "~";
    case tok!"private":
        return "-";
    case tok!"protected":
        return "#";
    case tok!"public":
        return "+";
    default:
        return "+";
    }
}

private string[] modifiers(const Declaration declaration) pure
{
    string[] modifiers = null;
    if (declaration.attributes.any!(a => a.attribute == tok!"abstract"))
        modifiers ~= "{abstract}";
    if (declaration.attributes.any!(a => a.attribute == tok!"static"))
        modifiers ~= "{static}";
    return modifiers;
}