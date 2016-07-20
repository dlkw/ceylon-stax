import ceylon.buffer.charset {
    utf8,
    Charset,
    utf16
}
import ceylon.collection {
    LinkedList,
    Queue,
    Stack,
    ArrayList,
    HashMap,
    MutableMap,
    ListMutator,
    MapMutator,
    MutableList
}

shared abstract class XMLEvent()
        of StartDocument | StartElement | EndElement | Characters | EntityReference | ProcessingInstruction | Comment | EndDocument | DTD
{
    
}

shared class StartDocument
        extends XMLEvent
{
    shared Boolean xmlDeclPresent;
    shared String version;
    shared String? encoding;
    shared Boolean? standalone;
    
    shared new present(String version, String? encoding, Boolean? standalone)
            extends XMLEvent()
    {
        xmlDeclPresent = true;
        this.version = version;
        this.encoding = encoding;
        this.standalone = standalone;
    }
    
    shared new absent extends XMLEvent()
    {
        xmlDeclPresent = false;
        this.version = "1.0";
        this.encoding = null;
        this.standalone = null;
    }
    
    shared actual String string
    {
        value sb = StringBuilder();
        sb.append("Start document XML ").append(version);
        if (xmlDeclPresent) {
            if (exists encoding) {
                sb.append(" encoding ").append(encoding);
            }
            else {
                sb.append(" (no encoding specified)");
            }
            if (exists standalone) {
                sb.append(" standalone: ").append(standalone.string);
            }
            else {
                sb.append(" (no standalone flag)");
            }
        }
        else {
            sb.append(" (no XML declaration present)");
        }
        return sb.string;
    }
}

shared class StartElement(expandedName, Boolean emptyElementTag = false, attributes = emptyMap, namespaceDeclarations = emptyMap)
        extends XMLEvent()
{
    shared QName expandedName;
    shared String localName=>expandedName.localName;
    shared String? prefix=>expandedName.prefix;
    shared String? namespaceName=>expandedName.namespaceName;
    shared Map<QName, String> attributes;
    shared Map<String, String> namespaceDeclarations;
    
    shared actual String string
    {
        value sb = StringBuilder();
        sb.append("Start element ");
        sb.append(expandedName.string);
        for (a in attributes) {
            sb.append("\n\tAttribute: ``a``");
        }
        for (nsDecl in namespaceDeclarations) {
            sb.append("\n\t").append(nsDeclString(nsDecl.key, nsDecl.item));
        }
        return sb.string;
    }
    
    String nsDeclString(String prefix, String uriReference)
    {
        if (prefix.empty) {
            if (uriReference.empty) {
                return "Namespace declaration: undefine default namespace";
            }
            else {
                return "Namespace declaration: default namespace->``uriReference``";
            }
        }
        return "Namespace declaration: ``prefix``->``uriReference``";
    }
}

shared class EndElement(shared QName name, Boolean emptyElementTag = false)
        extends XMLEvent()
{
    shared actual String string => "End element ``name``";
}

shared class Characters(shared String text, shared Boolean whitespace, shared Boolean ignorableWhitespace)
        extends XMLEvent()
{
    shared actual String string => "Text ->``text``<-``if(whitespace) then " (ws)" else ""``";
}

shared class EntityReference()
        extends XMLEvent()
{}

shared class ProcessingInstruction(shared String target, shared String instruction)
        extends XMLEvent()
{
    shared actual String string => "PI -> ``target``->``instruction``";
}

shared class Comment(shared String commentString)
        extends XMLEvent()
{
    shared actual String string => "Comment ->``commentString``<-";
}

shared class EndDocument()
        extends XMLEvent()
{
    shared actual String string => "End document";
}

shared class DTD()
        extends XMLEvent()
{}
