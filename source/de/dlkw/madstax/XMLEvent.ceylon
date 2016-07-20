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

"""
   Abstract base class for XML events.
"""
shared abstract class XMLEvent()
        of StartDocument | StartElement | EndElement | Characters | EntityReference | ProcessingInstruction | Comment | EndDocument | DTD
{}

"""
   The event representing the start of an XML document.
   
   Every well-formed XML document begins with this event. If the document contains an XML declaration, then
   [[xmlDeclPresent]] will be true, and the [[version]], [[encoding]] and [[standalone]] properties will
   be set according to the declaration.
"""
shared class StartDocument
        extends XMLEvent
{
    "`true` iff the XML document contains an XML declaration."
    shared Boolean xmlDeclPresent;
    
    "The XML specification version of the XML document. Will always be 1.0. Other versions are not supported."
    shared String version;
    
    "The encoding specified in the document's XML declaration or `null` if there is no encoding pseudo-attribute.
     
     Note that this may be different from the [[XMLEventReader.encoding]] value."
    shared String? encoding;

    "The value of the standalone pseudo-attribute (yes or no mapped to `true` resp. `false`) specified in the document's XML declaration, if present, else `null`."
    shared Boolean? standalone;
    
    "Creates a start document event when there's an XML declaration in the document."
    shared new present(String version, String? encoding, Boolean? standalone)
            extends XMLEvent()
    {
        xmlDeclPresent = true;
        this.version = version;
        this.encoding = encoding;
        this.standalone = standalone;
    }
    
    "Creates a start document event when there's no XML declaration in the document."
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

"""
   The event representing the start of an element.
   
   It is created for start element tags or for empty element tags. In the latter case, the [[emptyElementTag]] flag will
   be `true` and the StartElement event will be immediately followed by an EndElement event that also has its
   [[EndElement.emptyElementTag]] set to `true`.
"""
shared class StartElement(expandedName, emptyElementTag = false, attributes = emptyMap, namespaceDeclarations = emptyMap)
        extends XMLEvent()
{
    "The name of the element. The fields [[ExpandedName.namespaceName]] and [[ExpandedName.prefix]] will only
     be used (non-null) in the namespace-aware case."
    shared ExpandedName expandedName;
    
    "Will be set if this event corresponds to an empty element tag (e.g. `<element attr='val' />`)"
    shared Boolean emptyElementTag;
    
    "If namespace-aware, the localName of the element, else the name of the element."
    shared String localName=>expandedName.localName;
    
    "Conveniance shortcut for `expandedName.prefix`."
    shared String? prefix=>expandedName.prefix;

    "Conveniance shortcut for `expandedName.namespaceName`."
    shared String? namespaceName=>expandedName.namespaceName;

    "The attributes defined in the corresponding start element tag."
    shared Map<ExpandedName, String> attributes;
    
    "The namespace prefix binding declarations int the corresponding start element tag.
     Only used in namespace-aware mode; otherwise, the map will be empty and only the
     [[attributes]] map will be used."
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


"""
   The event representing the end of an element.

   It is created for end element tags or for empty element tags. In the latter case, it the end element event
   will have been immediately preceded by a start element event, and both of them will have their
   `emptyElementTag` flag set.
"""        
shared class EndElement(name, emptyElementTag = false)
        extends XMLEvent()
{
    "The name of the element. The fields [[ExpandedName.namespaceName]] and [[ExpandedName.prefix]] will only
     be used (non-null) in the namespace-aware case."
    shared ExpandedName name;
    
    "Will be set if this event corresponds to an empty element tag (e.g. `<element attr='val' />`)"
    shared Boolean emptyElementTag;
    
    shared actual String string => "End element ``name``";
}

"""
   The event representing text contents.
   
   For now, only the 5 predefined internal entities are supported (and always replaced).
"""
shared class Characters(text, whitespace, ignorableWhitespace)
        extends XMLEvent()
{
    "The text contents, including all whitespace."
    shared String text;
    
    "Indicates if the text consits of whitespace only."
    shared Boolean whitespace;
    
    "Not used for now."
    shared Boolean ignorableWhitespace;
    
    shared actual String string => "Text ->``text``<-``if(whitespace) then " (ws)" else ""``";
}

"""
   Not used for now.
"""
shared class EntityReference()
        extends XMLEvent()
{}

"""
   The event representing a processing instruction, `<?target instruction?>`.
"""
shared class ProcessingInstruction(target, instruction)
        extends XMLEvent()
{
    "The target of the processing instruction."
    shared String target;
    
    "The instruction (sometimes also called value) of the processing instruction."
    shared String instruction;
    
    shared actual String string => "PI -> ``target``->``instruction``";
}

"""
   The event representing a comment, `<!--comment-->`.
"""
shared class Comment(comment)
        extends XMLEvent()
{
    "The comment text."
    shared String comment;
    
    shared actual String string => "Comment ->``comment``<-";
}

"""
   The event representing the end of the XML document.
"""
shared class EndDocument()
        extends XMLEvent()
{
    shared actual String string => "End document";
}

"""
   Not used for now.
"""
shared class DTD()
        extends XMLEvent()
{}
