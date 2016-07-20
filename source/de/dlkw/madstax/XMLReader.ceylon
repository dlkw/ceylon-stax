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
    MapMutator,
    MutableList
}

"Error returned to signal a parsing error."
shared class ParseError(shared String msg){}
class ParseException(shared String msg) extends Exception(msg){}

class State of beforeProlog
        | prologLt
        | prologExclam
        | prologQuest
        | noXmlDecl
        | noXmlDeclLt
        | prologPI

        | rootEl
        | element
        | content
        | contentExclam
        | contentPI
        | elementTag
        | endElementTag
        | afterRoot

        | finished
{
    String s;
    shared new beforeProlog{s="beforeProlog";}
    shared new prologLt{s="prologLt";}
    shared new prologExclam{s="prologExclam";}
    shared new prologQuest{s="prologQuest";}
    shared new noXmlDecl{s="noXmlDecl";}
    shared new noXmlDeclLt{s="noXmlDeclLt";}
    shared new prologPI{s="prologPI";}
    shared new rootEl{s="rootEl";}

    shared new element{s="element";}
    shared new content{s="content";}
    shared new contentExclam{s="contentComment";}
    shared new contentPI{s="contentPI";}
    shared new elementTag{s="elementTag";}
    shared new endElementTag{s="endElementTag";}
    shared new afterRoot{s="afterRoot";}
    
    shared new finished{s="finished";}
    shared actual String string => s;
}

shared String defaultXmlVersion = "1.0";
shared String defaultXmlEncoding = "UTF-8";

shared class ExpandedName(localName, namespaceName=null, prefix=null)
{
    shared String localName;
    shared String? namespaceName;
    shared String? prefix;
    
    shared actual Boolean equals(Object that)
    {
        if (!is ExpandedName that) {
            return false;
        }
        
        if (that.localName != localName) {
            return false;
        }
        
        if (exists namespaceName) {
            return if (exists it = that.namespaceName) then it == namespaceName else false;
        }
        return that.namespaceName is Null;
    }

    shared actual Integer hash
    {
        return 31 * localName.hash + (if (exists it = namespaceName) then it.hash else 0);
    }
    
    shared actual String string
    {
        value sb = StringBuilder();
        sb.appendCharacter('"');
        if (exists it = prefix, !it.empty) {
            sb.append(it).appendCharacter(':');
        }
        sb.append(localName);
        if (exists it = namespaceName) {
            sb.appendCharacter('{').append(it).appendCharacter('}');
        }
        sb.appendCharacter('"');
        return sb.string;
    }
}

class ElementInfo(name, namespaceDeclarations)
{
    shared ExpandedName name;
    shared Map<String, String>? namespaceDeclarations;
}

"""
   Pull-parser for reading XML, offering XMLEvents to the calling application.
 
   This is a(n incomplete) non-validating XML processor according to the W3C's [Extensible Markup Language (XML) 1.0 (Fifth Edition)]
   (http://www.w3.org/TR/2008/REC-xml-20081126/). The major restriction is the missing support for DOCTYPE, so
   entities (other than the document entity) cannot be declared.
 
   The parser is optionally namespace-aware, supporting the W3C's [Namespaces in XML 1.0 (Third Edition)](http://www.w3.org/TR/2009/REC-xml-names-20091208/).
 
   During initialization with an input Sequential<Byte>, the XMLEventReader tries to heuristically detect the input's character encoding. This detection
   uses the encoding="..." pseudo-attribute of the XML declaration at the beginning of the document, if present. It
   can be overridden using the forcedEncoding parameter, which is useful if some external protocol (like MIME) specifies the encoding of the XML document.
   The encoding that the XMLEventReader uses can be queried via the `encoding` property.
   
   After initialization, the `XMLEvent`s can be retrieved via the `Iterator` mechanism, which may return a `ParseError` in case of well-formedness error.
"""
by("Dirk Lattermann")
throws(`class ParseException`)
shared class XMLEventReader(namespaceAware, input, forcedEncoding = null)
        satisfies Iterator<XMLEvent|ParseError>
{
    "Controls if the parser shall be namespace aware."
    shared Boolean namespaceAware;
    
    "The bytes that will be parsed into XMLEvents."
    {Byte*} input;
    
    "If non-null, the encoding that will be used to convert the [[input]] bytes to characters.
     If null, the encoding will be auto-detected from the input."
    Charset? forcedEncoding;
    
    throws(`class ParseException`)
    [Charset, Iterator<Byte>] guessCharset(Iterator<Byte> headIterator)
    {
        value b0 = headIterator.next();
        if (is Finished b0) {
            throw AssertionError("input too short to be an XML document");
        }
        value b1 = headIterator.next();
        if (is Finished b1) {
            throw AssertionError("input too short to be an XML document");
        }
        value b2 = headIterator.next();
        if (is Finished b2) {
            throw AssertionError("input too short to be an XML document");
        }
        value b3 = headIterator.next();
        if (is Finished b3) {
            throw AssertionError("input too short to be an XML document");
        }
        Byte[4] head = [b0, b1, b2, b3];

        AdHocEncoding guessedEncoding = guessEncoding(head);

        Charset charset;
        Iterator<Byte> newInput;
        switch (guessedEncoding)
        case (AdHocEncoding.utf8WithoutBOM) {
            charset = utf8;
            newInput = ChainingIterator({head.iterator(), headIterator});
        }
        case (AdHocEncoding.utf8WithBOM) {
            charset = utf8;
            newInput = headIterator;
        }
        case (AdHocEncoding.other) {
            charset = utf8;
            newInput = ChainingIterator({head.iterator(), headIterator});
        }
        case (AdHocEncoding.utf16beWithBOM) {
            charset = utf16;
            newInput = ChainingIterator({head.iterator(), headIterator});
        }
        case (AdHocEncoding.utf16leWithBOM) {
            charset = utf16;
            newInput = ChainingIterator({head.iterator(), headIterator});
        }
        
        return [charset, newInput];
    }
    
    Charset charset;
    Iterator<Byte> newIterator;
    if (exists forcedEncoding) {
        charset = forcedEncoding;
        newIterator = input.iterator();
    }
    else {
        value guessResult = guessCharset(input.iterator());
        charset = guessResult[0];
        newIterator = guessResult[1];
    }
    
    "The character encoding used to read the input. Either auto-detected or taken from [[forcedEncoding]]."
    shared String encoding = charset.name;

    value source = PositionPushbackSource(charset.decode(input).iterator());
    
    "The current reading position in the input, in characters, starting at 0."
    shared Integer offset => source.offset;
    
    "The line number of the current reading position, starting at 1."
    shared Integer line => source.line;
    
    "The column number in the current line, starting at 1."
    shared Integer column => source.column;
    
    MutableMap<String, String> internalEntities = HashMap<String, String>();
    internalEntities.putAll(predefinedEntities);
    internalEntities.put("ga", "aha<joi>mama</joi> ");
    
    Stack<PositionPushbackSource> entityRefSource = LinkedList<PositionPushbackSource>();
    
    variable State state = State.beforeProlog;
    
    Queue<XMLEvent> parsedEvents = LinkedList<XMLEvent>();

    NamespaceContextImpl namespaceContext = NamespaceContextImpl();
    Stack<ElementInfo> elementPath = LinkedList<ElementInfo>();

    Character|Finished nextChar()
    {
        while (exists s = entityRefSource.top) {
            value c = s.nextChar();
            if (is Finished c) {
                entityRefSource.pop();
            }
            else {
                return c;
            }
        }
        return source.nextChar();
    }
    
    void pushbackChar(Character character)
    {
        if (exists s = entityRefSource.top) {
            s.pushbackChar(character);
        }
        else {
            source.pushbackChar(character);
        }
    }

    "Reads the next portion of the input to return the next XMLEvent or ParseError. Finished after the end of the document."
    shared actual XMLEvent|ParseError|Finished next()
    {
        print(namespaceContext.bindings());
        try {
            return internalNext();
        }
        catch (ParseException e) {
            return ParseError(e.msg);
        }
    }
 
    throws(`class ParseException`)
    XMLEvent|Finished internalNext()
    {
        if (exists event = parsedEvents.accept()) {
            return event;
        }

        while (true) {
            switch (state)
            case (State.beforeProlog) {
                if (!is Finished c0 = source.nextChar()) {
                    Character c1;
                    if (isXmlWhitespace(c0)) {
                        source.pushbackChar(c0);
                        state = State.noXmlDecl;
                        return StartDocument.absent;
                    }
                    else {
                        c1 = c0;
                    }
                    
                    if (c1 == '<') {
                        state = State.prologLt;
                    }
                    else {
                        throw ParseException("text content before root element or wrong encoding (detected ``charset``)");
                    }
                }
                else {
                    throw ParseException("no root element");
                }
            }
            case (State.prologLt) {
                if (!is Finished c = source.nextChar()) {
                    if (c == '!') {
                        state = State.prologExclam;
                        return StartDocument.absent;
                    }
                    else if (c == '?') {
                        state = State.prologQuest;
                    }
                    else if (isNameStartChar(c)) {
                        source.pushbackChar(c);
                        state = State.rootEl;
                        return StartDocument.absent;
                    }
                    else {
                        throw ParseException("invalid name start character");
                    }
                }
                else {
                    throw ParseException("EOF while reading prolog");
                }
            }
            case (State.noXmlDecl) {
                if (!is Finished c = source.nextChar()) {
                    Character c1;
                    String? ws;
                    if (isXmlWhitespace(c)) {
                        value res = gatherWhitespace(c);
                        ws = res[0];
                        value cc = res[1];

                        if (is Finished cc) {
                            throw ParseException("EOF after tag opening");
                        }
                        c1 = cc;
                    }
                    else {
                        ws = null;
                        c1 = c;
                    }
                    
                    if (c1 == '<') {
                        state = State.noXmlDeclLt;
                        if (exists ws) {
                            return Characters(ws, true, true);
                        }
                    }
                    else {
                        throw ParseException("text content before root element");
                    }
                }
                else {
                    throw ParseException("no root element");
                }
            }
            case (State.noXmlDeclLt) {
                if (!is Finished c = source.nextChar()) {
                    if (c == '!') {
                        state = State.prologExclam;
                    }
                    else if (c == '?') {
                        state = State.prologPI;
                    }
                    else {
                        source.pushbackChar(c);
                        state = State.rootEl;
                    }
                }
                else {
                    throw ParseException("no root element");
                }
            }
            case (State.prologExclam) {
                if (!is Finished c = source.nextChar()) {
                    if (c == '-') {
                        value commentResult = readComment("-");
                        state = State.noXmlDecl;
                        return Comment(commentResult);
                    }
                    else if (c == 'D') {
                        throw ParseException("DOCTYPE not supported yet");
                    }
                    else {
                        throw ParseException("invalid tag beginning <!");
                    }
                }
                else {
                    throw ParseException("EOF while reading comment/doctype in prolog");
                }
            }
            case (State.prologQuest) {
                switch (it = checkWithPushbackOnFalse("xml"))
                case (finished) {
                    throw ParseException("EOF in XML declaration");
                }
                case (false) {
                    state = State.prologPI;
                }
                case (true) {
                    value res = gatherWhitespace();
                    value c = res[1];
                    if (is Finished c) {
                        throw ParseException("EOF in XML declaration");
                    }
                    if (res[0].empty) {
                        pushbackChar(c);
                        pushbackChar('l');
                        pushbackChar('m');
                        pushbackChar('x');
                    }
                    else {
                        pushbackChar(c);
                        value startDocument = readXmlDeclaration();
                        state = State.noXmlDecl;
                        return startDocument;
                    }
                }
            }
            case (State.prologPI) {
                value pi = readProcessingInstruction();
                state = State.noXmlDecl;
                return ProcessingInstruction(pi[0], pi[1]);
            }
            case (State.rootEl) {
                state = State.element;
            }
            case (State.element) {
                value nameResult = gatherName();

                value c0 = nameResult[1];
                
                value rr = gatherAttributes(c0);
                
                Character c1 = rr[1];

                if (c1 == '/') {
                    switch (it = check(">"))
                    case (finished) {
                        throw ParseException("EOF in close empty tag");
                    }
                    case (false) {
                        throw ParseException("invalid empty tag close");
                    }
                    case (true) {
                        if (is Null parentEl = elementPath.top) {
                            state = State.afterRoot;
                        }
                        else {
                            state = State.content;
                        }
                        
                        if (namespaceAware) {
                            value nsBindingDeclsAndAttribs = determineNsBindingDeclsAndAttribs(rr[0]);
                            value declarations = nsBindingDeclsAndAttribs[0];
                            
                            declarations.each((binding) => namespaceContext.push(binding));
                            
                            value expandedName = expandName(nameResult[0], true);
                            value attribsMap = map(nsBindingDeclsAndAttribs[1].map((e)=>expandName(e.key, false) -> e.item));
                            
                            parsedEvents.offer(EndElement(expandedName, true));
                            value startElement = StartElement(expandedName, true, attribsMap, nsBindingDeclsAndAttribs[0]);

                            // FIXME after the StartElement event, but before the immediately following EndElement, the XMLReader's namespaceContext won't reflect the namespace declarations in this empty element tag
                            
                            declarations.each((binding) => namespaceContext.pop(binding.key));

                            return startElement;
                        }
                        else {
                            value name = ExpandedName(nameResult[0]);
                            value attribsMap = map(rr[0].map((attrib) => ExpandedName(attrib.key) -> attrib.item));
                            parsedEvents.offer(EndElement(name, true));
                            return StartElement(name, true, attribsMap);
                        }
                    }
                }
                else if (c1 == '>') {
                    state = State.content;
                    if (namespaceAware) {
                        value nsBindingDeclsAndAttribs = determineNsBindingDeclsAndAttribs(rr[0]);
                        value declarations = nsBindingDeclsAndAttribs[0];
                        
                        declarations.each((binding) => namespaceContext.push(binding));
                        
                        value expandedName = expandName(nameResult[0], true);
                        value attribsMap = map(nsBindingDeclsAndAttribs[1].map((e)=>expandName(e.key, false) -> e.item));
                        
                        elementPath.push(ElementInfo(expandedName, declarations));
                        return StartElement(expandedName, false, attribsMap, nsBindingDeclsAndAttribs[0]);
                    }
                    else {
                        value name = ExpandedName(nameResult[0]);
                        value attribsMap = map(rr[0].map((attrib) => ExpandedName(attrib.key) -> attrib.item));
                        elementPath.push(ElementInfo(name, null));
                        return StartElement(name, false, attribsMap);
                    }
                }
                else {
                    throw ParseException("invalid character in start element tag");
                }
            }
            case (State.content) {
                // more madness...
                variable Boolean stay = true;
                
                variable Boolean whitespace = true;
                value sb = StringBuilder();
                while (stay) {
                    stay = false;

                    value contentResult = gatherTextContent();
                    sb.append(contentResult[0]);
                    whitespace &&= contentResult[2];

                    if (contentResult[1] == '<') {
                        value c = nextChar();
                        if (is Finished c) {
                            throw ParseException("EOF in element start");
                        }
                        if (c == '!') {
                            state = State.contentExclam;
                        }
                        else if (c == '?') {
                            state = State.contentPI;
                        }
                        else {
                            pushbackChar(c);
                            state = State.elementTag;
                        }
                    }
                    else if (contentResult[1] == '&') {
                        value c0 = nextChar();
                        if (is Finished c0) {
                            throw ParseException("EOF in content");
                        }
                        if (c0 == '#') {
                            value cr = resolveCharacterReference(nextChar);
                            whitespace &&= isXmlWhitespace(cr);
                            sb.appendCharacter(cr);
                        }
                        else {
                            value ref = gatherName(c0);
                            if (ref[1] != ';') {
                                throw ParseException("entity reference does not finish with ;");
                            }
                            
                            value replacementText = internalEntities[ref[0]];
                            if (exists replacementText) {
                                entityRefSource.push(PositionPushbackSource(replacementText.iterator()));
                            }
                            else {
                                throw ParseException("entity not defined");
                            }
                        }
                        // yet more madness...
                        stay = true;
                    }
                }
                if (!sb.empty) {
                    // fixme ignorable whitespace?!
                    return Characters(sb.string, whitespace, false);
                }
            }
            case (State.contentExclam) {
                value c1 = nextChar();
                if (is Finished c1) {
                    throw ParseException("EOF in start comment/CDATA section");
                }
                if (c1 == '-') {
                    value commentResult = readComment("-");
                    state = State.content;
                    return Comment(commentResult);
                }
                else if (c1 == '[') {
                    value res = check("CDATA[");
                    switch (res)
                    case (finished | false) {
                        throw ParseException("invalid CDATA section start");
                    }
                    case (true) {
                        value cdataResult = gatherCData();
                        state = State.content;
                        return Characters(cdataResult[0], cdataResult[1], false); 
                    }
                }
                else {
                    throw ParseException("invalid start comment/CDATA section");
                }
            }
            case (State.contentPI) {
                value pi = readProcessingInstruction();
                state = State.content;
                return ProcessingInstruction(pi[0], pi[1]);
            }
            case (State.elementTag) {
                if (!is Finished c = nextChar()) {
                    if (c == '/') {
                        state = State.endElementTag;
                    }
                    else {
                        pushbackChar(c);
                        state = State.element;
                    }
                }
                else {
                    throw ParseException("EOF in tag");
                }
            }
            case (State.endElementTag) {
                value nameResult = gatherName();
                
                value c0 = nameResult[1];
                
                Character c1;
                if (isXmlWhitespace(c0)) {
                    value [ws, c] = gatherWhitespace(c0);
                    if (is Finished c) {
                        throw ParseException("EOF in element tag");
                    }
                    c1 = c;
                }
                else {
                    c1 = c0;
                }
                
                if (c1 != '>') {
                    throw ParseException("Invalid end element tag");
                }
                
                //FIXME check name match
                value expectedName = elementPath.pop();
                assert (exists expectedName);
                
                ExpandedName name;
                if (namespaceAware) {
                    assert (exists expectedPrefix = expectedName.name.prefix);
                    name = expandName(nameResult[0], true);
                    assert (exists endedPrefix = name.prefix);
                    if (expectedName.name.localName != name.localName || expectedPrefix != endedPrefix) {
                        throw ParseException("end tag not matching start tag");
                    }

                    assert (exists declarations = expectedName.namespaceDeclarations);
                    declarations.each((decl) => namespaceContext.pop(decl.key));
                }
                else {
                    if (expectedName.name.localName != nameResult[0]) {
                        throw ParseException("end tag not matching start tag");
                    }
                    name = ExpandedName(nameResult[0]);
                }
                
                if (exists it = elementPath.top) {
                    state = State.content;
                }
                else {
                    state = State.afterRoot;
                }
                return EndElement(name);
            }
            case (State.afterRoot) {
                if (!is Finished c = source.nextChar()) {
                    if (isXmlWhitespace(c)) {
                        value wsResult = gatherWhitespace(c);
                        if (!is Finished it = wsResult[1]) {
                            source.pushbackChar(it);
                        }
                        return Characters(wsResult[0], true, false);
                    }
                    if (c == '<') {
                        if (!is Finished c1 = source.nextChar()) {
                            if (c1 == '!') {
                                value commentResult = readComment("--");
                                return Comment(commentResult);
                            }
                            else if (c1 == '?') {
                                value pi = readProcessingInstruction();
                                return ProcessingInstruction(pi[0], pi[1]);
                            }
                            else {
                                throw ParseException("multiple root elements");
                            }
                        }
                        else {
                            throw ParseException("EOF in comment/processing instruction after root element");
                        }
                    }
                    else {
                        throw ParseException("invalid text after root element");
                    }
                }
                else {
                    state = State.finished;
                    return EndDocument();
                }
            }
            case (State.finished) {
                return finished;
            }
            else {
                throw AssertionError("unknown state ``state``");
            }
        }
    }

    Boolean|Finished check(String rest) {
        for (sc in rest) {
            if (!is Finished c = nextChar()) {
                if (c != sc) {
                    return false;
                }
            }
            else {
                return finished;
            }
        }
        return true;
    }
    
    Boolean|Finished checkWithPushbackOnFalse(String rest) {
        value sb = StringBuilder();
        for (sc in rest) {
            if (!is Finished c = nextChar()) {
                if (c != sc) {
                    sb.reversed.each((pb)=>pushbackChar(pb));
                    return false;
                }
            }
            else {
                return finished;
            }
        }
        return true;
    }
    
    [String, Character|Finished] gatherWhitespace(Character? first = null)
    {
        StringBuilder sb = StringBuilder();
        if (exists first) {
            sb.appendCharacter(first);
        }
        
        while (true) {
            value c = nextChar();
            
            if (!is Finished c) {
                if (isXmlWhitespace(c)) {
                    sb.appendCharacter(c);
                }
                else {
                    return [sb.string, c];
                }
            }
            else {
                return [sb.string, c];
            }
        }
    }
    
    [String, Character] gatherVersionDecimal() {
        value sb = StringBuilder();
        while (true) {
            value c = nextChar();
            if (is Finished c) {
                throw ParseException("EOF in XML version number");
            }
            if ('0' <= c <= '9') {
                sb.appendCharacter(c);
            }
            else {
                if (sb.empty) {
                    throw ParseException("non-digit in XML version number decimal place");
                }
                else {
                    return [sb.string, c];
                }
            }
        }
    }

    [String, Character] gatherName(Character? first = null)
    {
        value firstChar = first else nextChar();
        if (is Finished firstChar) {
            throw ParseException("EOF in Name");
        }
        if (!isNameStartChar(firstChar)) {
            throw ParseException("Invalid name starting character '``firstChar``'");
        }
        StringBuilder sb = StringBuilder().appendCharacter(firstChar);
        while (true) {
            value c = nextChar();
            if (is Finished c) {
                throw ParseException("EOF in Name");
            }
            if (isNameChar(c)) {
                sb.appendCharacter(c);
            }
            else {
                return [sb.string, c];
            }
        }
    }
    
    String gatherComment()
    {
        value sb = StringBuilder();
        while (true) {
            value c0 = nextChar();
            if (is Finished c0) {
                throw ParseException("EOF in comment");
            }
            if (c0 == '-') {
                value c1 = nextChar();
                if (is Finished c1) {
                    throw ParseException("EOF in comment");
                }
                if (c1 == '-') {
                    value c2 = nextChar();
                    if (is Finished c2) {
                        throw ParseException("EOF in comment");
                    }
                    if (c2 == '>') {
                        return sb.string;
                    }
                    throw ParseException("-- in comment");
                }
                if (isChar(c1)) {
                    sb.appendCharacter(c0).appendCharacter(c1);
                }
                else {
                    throw ParseException("invalid character in comment");
                }
            }
            if (isChar(c0)) {
                sb.appendCharacter(c0);
            }
            else {
                throw ParseException("invalid character in comment");
            }
        }
    }
    
    [String, Boolean] gatherCData()
    {
        variable Boolean isWhitespace = true;
        value sb = StringBuilder();
        while (true) {
            value c0 = nextChar();
            if (is Finished c0) {
                throw ParseException("EOF in comment");
            }
            if (c0 == ']') {
                value c1 = nextChar();
                if (is Finished c1) {
                    throw ParseException("EOF in comment");
                }
                if (c1 == ']') {
                    value c2 = nextChar();
                    if (is Finished c2) {
                        throw ParseException("EOF in comment");
                    }
                    if (c2 == '>') {
                        return [sb.string, isWhitespace];
                    }
                    throw ParseException("-- in comment");
                }
                if (isChar(c1)) {
                    isWhitespace &&= isXmlWhitespace(c1);
                    sb.appendCharacter(c0).appendCharacter(c1);
                }
                else {
                    throw ParseException("invalid character in comment");
                }
            }
            if (isChar(c0)) {
                isWhitespace &&= isXmlWhitespace(c0);
                sb.appendCharacter(c0);
            }
            else {
                throw ParseException("invalid character in comment");
            }
        }
    }
    
    [String, Character, Boolean, Boolean] gatherTextContent()
    {
        variable Boolean isWhitespace = true;
        value sb = StringBuilder();
        while (true) {
            value c0 = nextChar();
            if (is Finished c0) {
                throw ParseException("EOF in text content");
            }
            
            if (c0 == '<' || c0 == '&') {
                return [sb.string, c0, isWhitespace, false];
            }
            
            if (!isChar(c0)) {
                throw ParseException("invalid character in text content");
            }
            
            if (c0 == ']') {
                value c1 = nextChar();
                if (is Finished c1) {
                    throw ParseException("EOF in text content");
                }
                if (c1 == ']') {
                    value c2 = nextChar();
                    if (is Finished c2) {
                        throw ParseException("EOF in text content");
                    }
                    if (c2 == '>') {
                        /* FIXME this is a hack, text content until here should be returned as
                         * Characters and the the next event fetch result in this error.
                         */
                        throw ParseException("]]> in text content not allowed");
                    }
                    else {
                        pushbackChar(c2);
                        pushbackChar(c1);
                        isWhitespace = false;
                        sb.appendCharacter(c0);
                    }
                }
                else {
                    pushbackChar(c1);
                    isWhitespace = false;
                    sb.appendCharacter(c0);
                }
            }
            else {
                isWhitespace &&= isXmlWhitespace(c0);
                sb.appendCharacter(c0);
            }
        }
    }
    
    String gatherUntilQuestGt(Character first)
    {
        variable Character|Finished crs = first;
        StringBuilder sb = StringBuilder();
        while (true) {
            value c = crs;
            if (is Finished c) {
                throw ParseException("EOF in PI or XMLDecl");
            }
            if (c == '?') {
                value c2 = nextChar();
                if (is Finished c2) {
                    throw ParseException("EOF in PI or XMLDecl");
                }
                if (c2 == '>') {
                    return sb.string;
                }
                sb.appendCharacter(c);
                sb.appendCharacter(c2);
            }
            else {
                sb.appendCharacter(c);
            }
            crs = nextChar();
        }
    }
    
    StartDocument readXmlDeclaration()
    {
        value versionName = check("version");
        switch (versionName)
        case (finished) {
            throw ParseException("EOF in XML declaration");
        }
        case (false) {
            throw ParseException("version must be specified in XML declaration");
        }
        case (true) {
            checkAttrEq();
        }
        value ws = nextChar();
        if (is Finished ws) {
            throw ParseException("EOF in XML declaration");
        }
        Character qExpected;
        if (isXmlWhitespace(ws)) {
            value wsResult1 = gatherWhitespace(ws);
            if (!is Finished it1 = wsResult1[1]) {
                qExpected = it1;
            }
            else {
                throw ParseException("EOF after attribute name");
            }
        }
        else {
            qExpected = ws;
        }
        if (qExpected != '"' && qExpected != '\'') {
            throw ParseException("invalid attribute value delimiter in XML declaration");
        }
        
        value ck = check("1.");
        String version;
        switch (ck)
        case (finished) {
            throw ParseException("EOF in XML version");
        }
        case (false) {
            throw ParseException("XML version must begin with \"1.\"");
        }
        case (true) {
            value versionDecimal = gatherVersionDecimal();
            if (versionDecimal[1] != qExpected) {
                throw ParseException("non-decimal in XML version decimal place");
            }
            version = "1." + versionDecimal[0];
        }
        
        
        
        
        
        value [ws2, c] = gatherWhitespace();
        if (is Finished c) {
            throw ParseException("EOF in XML declaration");
        }
        
        Character cnext;
        String? encoding;
        if (c == 'e') {
            value enc = check("ncoding");
            
            value eqRes = checkAttrEq();

            value ws3 = nextChar();
            if (is Finished ws3) {
                throw ParseException("EOF in XML declaration");
            }
            Character qExpected2;
            if (isXmlWhitespace(ws3)) {
                value wsResult1 = gatherWhitespace(ws3);
                if (!is Finished it1 = wsResult1[1]) {
                    qExpected2 = it1;
                }
                else {
                    throw ParseException("EOF after attribute name");
                }
            }
            else {
                qExpected2 = ws3;
            }
            value encValue = readXmlDeclEncodingValue(qExpected2);
            encoding = encValue;

            value [ws4, c2] = gatherWhitespace();
            if (is Finished c2) {
                throw ParseException("EOF in XML declaration");
            }
            cnext = c2;
        }
        else {
            encoding = null;
            cnext = c;
        }
        
        Character cnext2;
        Boolean? standalone;
        if (cnext == 's') {
            value std = check("tandalone");

            checkAttrEq();
            
            value ws3 = nextChar();
            if (is Finished ws3) {
                throw ParseException("EOF in XML declaration");
            }
            Character qExpected2;
            if (isXmlWhitespace(ws3)) {
                value wsResult1 = gatherWhitespace(ws3);
                if (!is Finished it1 = wsResult1[1]) {
                    qExpected2 = it1;
                }
                else {
                    throw ParseException("EOF after attribute name");
                }
            }
            else {
                qExpected2 = ws3;
            }
            value staValue = readYesNoValue(qExpected2);
            standalone = staValue;
            
            value [ws4, c2] = gatherWhitespace();
            if (is Finished c2) {
                throw ParseException("EOF in XML declaration");
            }
            cnext2 = c2;
        }
        else {
            standalone = null;
            cnext2 = cnext;
        }

        if (cnext2 != '?') {
            throw ParseException("invalid attr in XML declaration");
        }
        value c3 = nextChar();
        if (is Finished c3) {
            throw ParseException("EOF in XML declaration");
        }
        if (c3 != '>') {
            throw ParseException("invalid XML declaration");
        }

        return StartDocument.present(version, encoding, standalone);
    }
    
    [String, String] readProcessingInstruction()
    {
        if (!is Finished c = nextChar()) {
            value targetRes = gatherName(c);
            String target = targetRes[0];
            if (target == "xml") {
                throw ParseException("forbidden processing instruction target \"xml\"");
            }
            Character c0 = targetRes[1];
            if (!isXmlWhitespace(c0)) {
                throw ParseException("whitespace expected after processing instruction target");
            }
            value wsRes = gatherWhitespace(c0);
            value c1 = wsRes[1];
            if (is Finished c1) {
                throw ParseException("EOF in processing instruction");
            }
            value instruction = gatherUntilQuestGt(c1);
            return [target, instruction];
        }
        else {
            throw ParseException("EOF while reading processing instruction");
        }
    }
    
    
    String readComment(String startStringToCheck)
    {
        switch (it = check(startStringToCheck))
        case (finished) {
            throw ParseException("EOF while reading comment");
        }
        case (false) {
            throw ParseException("missing second - in comment start");
        }
        case (true) {
            value commentResult = gatherComment();
            return commentResult;
        }
    }

    [Map<String,String>, Character] gatherAttributes(Character first)
    {
        value result = HashMap<String, String>();
        variable Character c = first;
        while (true) {
            if (c == '>' || c == '/') {
                return [result, c];
            }
            if (c == ' ') {
                value res = gatherWhitespace(c)[1];
                if (is Finished res) {
                    throw ParseException("EOF in start element tag");
                }
                if (res == '>' || res == '/') {
                    return [result, res];
                }
                value attribute = readAttribute(res);
                if (exists prev = result.put(attribute.key, attribute.item)) {
                    throw ParseException("duplicate attribute key");
                }
                value c0 = nextChar();
                if (is Finished c0) {
                    throw ParseException("EOF in start element tag");
                }
                c = c0;
            }
            else {
                throw ParseException("need whitespace before attribute");
            }
        }
    }
    
    <String->String> readAttribute(Character first)
    {
        value nameResult = gatherName(first);
        value attributeName = nameResult[0];
        
        checkAttrEq(nameResult[1]);

        value wsResult2 = gatherWhitespace();
        if (!is Finished it2 = wsResult2[1]) {
            value attributeValue = readAttributeValue(it2);
            return attributeName->attributeValue;
        }
        else {
            throw ParseException("EOF while expecting attribute value");
        }
    }
    
    void checkAttrEq(Character? first = null)
    {
        Character c;
        if (exists first) {
            c = first;
        }
        else {
            value cc = nextChar();
            if (is Finished cc) {
                throw ParseException("EOF after attribute name");
            }
            c = cc;
        }
        Character eqExpected;
        if (isXmlWhitespace(c)) {
            value wsResult1 = gatherWhitespace(c);
            if (!is Finished it1 = wsResult1[1]) {
                eqExpected = it1;
            }
            else {
                throw ParseException("EOF after attribute name");
            }
        }
        else {
            eqExpected = c;
        }
        
        if (eqExpected != '=') {
            throw ParseException("missing = sign after attribute name");
        }
    }
    
    String readAttributeValue(Character first)
    {
        if (first != '\'' && first != '"') {
            throw ParseException("invalid attribute value delimiter");
        }
        value sb = StringBuilder();
        while (true) {
            value c = nextChar();
            if (is Finished c) {
                throw ParseException("EOF in attribute value");
            }
            if (c == first) {
                return normalizeAttributeValue(sb.string, true);
            }
            // & is allowed to accept references.
            if (c == '<' || !isChar(c)) {
                throw ParseException("invalid character in attribute value");
            }
            sb.appendCharacter(c);
        }
    }
    
    String readXmlDeclEncodingValue(Character first)
    {
        if (first != '\'' && first != '"') {
            throw ParseException("invalid attribute value delimiter");
        }
        value sb = StringBuilder();

        // first character
        value c0 = nextChar();
        if (is Finished c0) {
            throw ParseException("EOF in attribute value");
        }
        if (c0 == first) {
            return sb.string;
        }
        if ('a' <= c0 <= 'z' || 'A' <= c0 <= 'Z') {
            sb.appendCharacter(c0);
        }
        else {
            throw ParseException("invalid character in attribute value");
        }

        while (true) {
            value c = nextChar();
            if (is Finished c) {
                throw ParseException("EOF in attribute value");
            }
            if (c == first) {
                return sb.string;
            }
            if ('a' <= c <= 'z' || 'A' <= c <= 'Z' || '0' <= c <= '9' || c == '-' || c == '_' || c == '.') {
                sb.appendCharacter(c);
            }
            else {
                throw ParseException("invalid character in encoding attribute value");
            }
        }
    }
    
    Boolean readYesNoValue(Character first)
    {
        if (first != '\'' && first != '"') {
            throw ParseException("invalid attribute value delimiter");
        }
        value sb = StringBuilder();
        
        while (true) {
            value c = nextChar();
            if (is Finished c) {
                throw ParseException("EOF in attribute value");
            }
            if (c == first) {
                if (sb.string == "yes") {
                    return true;
                }
                else if (sb.string == "no") {
                    return false;
                }
                else {
                    throw ParseException("standalone value must be yes or no");
                }
            }
            if (c in "yesno") {
                sb.appendCharacter(c);
            }
            else {
                throw ParseException("standalone value must be yes or no");
            }
        }
    }
    
    ExpandedName expandName(String name, Boolean useDefaultNamespace)
    {
        value comps = name.split(':'.equals).sequence();
        value comp0 = comps[0];
        assert (exists comp0);
        if (comp0.empty) {
            throw ParseException("name starting with colon (:) not allowed");
        }
        
        value comp1 = comps[1];
        if (exists comp1) {
            value comp2 = comps[2];
            if (exists comp2) {
                throw ParseException("name may contain colon (:) as prefix separator only");
            }
            value namespaceName = namespaceContext.top(comp0);
            if (!exists namespaceName) {
                throw ParseException("undefined prefix ``comp0``");
            }
            return ExpandedName(comp1, namespaceName, comp0);
        }
        else if (useDefaultNamespace) {
            value namespaceName = namespaceContext.top("");
            return ExpandedName(comp0, namespaceName, "");
        }
        else {
            return ExpandedName(comp0, null, "");
        }
    }
}

Boolean isXmlWhitespace(Character|Finished c)
{
    return (c in "\{SPACE}\{CHARACTER TABULATION}\{CARRIAGE RETURN (CR)}\{LINE FEED (LF)}");
}

Boolean isChar(Character c) {
    if (isXmlWhitespace(c)) {
        return true;
    }
    if (c in '\{#21}'..'\{#d7ff}') {
        return true;
    }
    if (c in '\{#e000}'..'\{#fffd}') {
        return true;
    }
    if (c in '\{#010000}'..'\{#10ffff}') {
        return true;
    }
    return false;
}

Boolean isNameStartChar(Character c)
{
    if (c in 'a'..'z') {
        return true;
    }
    if (c in 'A'..'Z') {
        return true;
    }
    if (c in ":_") {
        return true;
    }
    if (c in '\{#c0}'..'\{#d6}') {
        return true;
    }
    if (c in '\{#d8}'..'\{#f6}') {
        return true;
    }
    if (c in '\{#f8}'..'\{#02ff}') {
        return true;
    }
    if (c in '\{#0370}'..'\{#037d}') {
        return true;
    }
    if (c in '\{#037f}'..'\{#1fff}') {
        return true;
    }
    if (c in '\{#200c}'..'\{#200d}') {
        return true;
    }
    if (c in '\{#2070}'..'\{#218f}') {
        return true;
    }
    if (c in '\{#2c00}'..'\{#2fef}') {
        return true;
    }
    if (c in '\{#3001}'..'\{#d7ff}') {
        return true;
    }
    if (c in '\{#f900}'..'\{#fdcf}') {
        return true;
    }
    if (c in '\{#fdf0}'..'\{#fffd}') {
        return true;
    }
    if (c in '\{#010000}'..'\{#0effff}') {
        return true;
    }
    return false;
}

Boolean isNameChar(Character c)
{
    if (isNameStartChar(c)) {
        return true;
    }
    if (c in '0'..'9') {
        return true;
    }
    if (c in "-.\{#b7}") {
        return true;
    }
    if (c in '\{#0300}'..'\{#036f}') {
        return true;
    }
    if (c in '\{#203f}'..'\{#2040}') {
        return true;
    }
    return false;
}

shared String namespace_xml = "http://www.w3.org/XML/1998/namespace";
shared String namespace_xmlns = "http://www.w3.org/2000/xmlns/";

[Map<String, String>, List<String->String>] determineNsBindingDeclsAndAttribs(Map<String, String> attribsKeyValue)
{
    [MutableMap<String, String>, MutableList<String->String>] res = [HashMap<String, String>(), ArrayList<String->String>()];
    attribsKeyValue.each((entry)
    {
        void bind(MapMutator<String, String> decls, String prefix, String uriReference)
        {
            if (prefix.any((c)=>c == ':')) {
                throw ParseException("prefix may not contain a colon (:)");
            }
            if (uriReference.empty) {
                if (!prefix.empty) {
                    throw ParseException("prefixes may not be undeclared");
                }
            }
            else if (uriReference == namespace_xml && prefix != "xml") {
                throw ParseException("namespace ``namespace_xml`` may be bound to prefix xml only");
            }
            else if (uriReference == namespace_xmlns) {
                throw ParseException("namespace ``namespace_xmlns`` may not be bound to any prefix nor as default namespace");
            }
            decls.put(prefix, uriReference);
        }
        
       if (entry.key.startsWith("xmlns")) {
            if (!entry.key.longerThan(5)) {
                bind(res[0], "", entry.item);
            }
            else {
                if (exists colon = entry.key[5], colon == ':') {
                    value prefix = entry.key.spanFrom(6);
                    if (prefix.empty) {
                        throw ParseException("namespace prefix to define missing");
                    }
                    else {
                        if (exists it = res[0].get(prefix)) {
                            throw ParseException("namespace prefix defined twice in element");
                        }
                        if (prefix.startsWith("xml")) {
                            if (!prefix.longerThan(3)) {
                                if (entry.item != namespace_xml) {
                                    throw ParseException("prefix xml may be redeclared as bound to ``namespace_xml`` only");
                                }
                                else {
                                    bind(res[0], prefix, entry.item);
                                }
                            }
                            else {
                                if (prefix.equals("xmlns")) {
                                    throw ParseException("prefix xmlns may not be redeclared");
                                }
                            }
                        }
                        else {
                            bind(res[0], prefix, entry.item);
                        }
                    }
                }
                else {
                    // attribute starting with xmnls#, where # is a Character, but not a colon
                    res[1].add(entry);
                }
            }
       }
       else {
           res[1].add(entry);
       }
       return res;
    });
    return res;
}

class AdHocEncoding
        of utf8WithoutBOM
        | utf8WithBOM
        | utf16beWithBOM
        | utf16leWithBOM
        | other
{
    String s;
    shared new utf8WithoutBOM{s="UTF-8 without BOM";}
    shared new utf8WithBOM{s="UTF-8 with BOM";}
    shared new utf16beWithBOM{s="UTF-16BE with BOM";}
    shared new utf16leWithBOM{s="UTF-16LE with BOM";}
    shared new other{s="UTF-8 without BOM, no XML declaration";}
    shared actual String string => s;
}

/*
B*00 00 FE FF 	UCS-4, big-endian machine (1234 order)
C*FF FE 00 00 	UCS-4, little-endian machine (4321 order)
D*00 00 FF FE 	UCS-4, unusual octet order (2143)
A*FE FF 00 00 	UCS-4, unusual octet order (3412)
E*FE FF ## ## 	UTF-16, big-endian
F*FF FE ## ## 	UTF-16, little-endian
G*EF BB BF 	UTF-8

Without a Byte Order Mark:
H*00 00 00 3C 	UCS-4 or other encoding with a 32-bit code unit and ASCII characters encoded as ASCII values, in respectively big-endian (1234), little-endian (4321) and two unusual byte orders (2143 and 3412). The encoding declaration must be read to determine which of UCS-4 or other supported 32-bit encodings applies.
I*3C 00 00 00
J*00 00 3C 00
K*00 3C 00 00
L*00 3C 00 3F 	UTF-16BE or big-endian ISO-10646-UCS-2 or other encoding with a 16-bit code unit in big-endian order and ASCII characters encoded as ASCII values (the encoding declaration must be read to determine which)
M*3C 00 3F 00 	UTF-16LE or little-endian ISO-10646-UCS-2 or other encoding with a 16-bit code unit in little-endian order and ASCII characters encoded as ASCII values (the encoding declaration must be read to determine which)
N*3C 3F 78 6D 	UTF-8, ISO 646, ASCII, some part of ISO 8859, Shift-JIS, EUC, or any other 7-bit, 8-bit, or mixed-width encoding which ensures that the characters of ASCII have their normal positions, width, and values; the actual encoding declaration must be read to detect which of these applies, but since all of these encodings use the same bit patterns for the relevant ASCII characters, the encoding declaration itself may be read reliably
O*4C 6F A7 94 	EBCDIC (in some flavor; the full encoding declaration must be read to tell which code page is in use)
*Other	UTF-8 without an encoding declaration, or else the data stream is mislabeled (lacking a required encoding declaration), corrupt, fragmentary, or enclosed in a wrapper of some kind
*/

throws(`class ParseException`)
AdHocEncoding guessEncoding(Byte[4] start)
{
    if (start[0] == #3c.byte) {
        if (start[1] == #3f.byte) {
            // 3c 3f, N UTF-8 without BOM, charset decl unnecessary, but may be any ASCII-valued 8bit encoding
            return AdHocEncoding.utf8WithoutBOM;
        }
        else if (start[1] == #00.byte) {
            if (start[2] == #3f.byte) {
                // 3c 00 3f, M UTF-16LE without BOM
                throw ParseException("detected 16bit ASCII-encoded <? in little endian order, but UTF-16LE (without BOM) unsupported");
            }
            else if (start[2] == #00.byte) {
                // 3c 00 00, I maybe UTF-32LE without BOM
                throw ParseException("detected 32bit ASCII-encoded < in little endian order, but UTF-32LE (without BOM) unsupported");
            }
            else {
                // unknown, using UTF-8, no charset decl found, only UTF-8 allowed.
                return AdHocEncoding.other;
            }
        }
        else {
            // unknown, using UTF-8, no charset decl found, only UTF-8 allowed.
            return AdHocEncoding.other;
        }
    }
    else if (start[0] == #fe.byte && start[1] == #ff.byte) {
        if (start[2] == #00.byte && start[3] == #00.byte) {
            // fe ff 00 00, D mixed-endian UTF-32 with BOM
            throw ParseException("detected 32bit BOM in unusual order, but UTF-32 (with BOM) unsupported");
        }
        else {
            // fe ff ## ##, E UTF-16BE with BOM, charset decl unnecessary
            return AdHocEncoding.utf16beWithBOM;
        }
    }
    else if (start[0] == #ff.byte && start[1] == #fe.byte) {
        if (start[2] == #00.byte && start[3] == #00.byte) {
            // ff fe 00 00, C UTF-32LE with BOM
            throw ParseException("detected 32bit BOM in little endian order, UTF-32LE (with BOM) unsupported");
        }
        else {
            // ff fe ## ##, F UTF-16LE with BOM, charset decl unnecessary, but UTF-16 or UTF-16BE accepted
            return AdHocEncoding.utf16leWithBOM;
        }
    }
    else if (start[0] == #00.byte) {
        if (start[1] == #3c.byte && start[2] == #00.byte) {
            if (start[3] == #3f.byte) {
                // 00 3c 00 3f, L UTF-16BE without BOM, or similar
                throw ParseException("detected 16bit ASCII-encoded <? in big endian order, but UTF-16BE (without BOM) unsupported");
            }
            else if (start[3] == #00.byte) {
                // 00 3c 00 00, K mixed-endian UTF-32 without BOM
                throw ParseException("detected 32bit ASCII-encoded < in unusual order, but UTF-32 (without BOM) unsupported");
            }
            else {
                // 00 3c 00 ##, probably UTF-16BE (without BOM), but without charset decl., which is an error
                throw ParseException("probably UTF-16BE (without BOM), but without charset declaration in violation to XML spec. UTF-16BE (without BOM) unsupported anyway.");
            }
        }
        else if (start[1] == #00.byte) {
            if (start[2] == #fe.byte) {
                // 00 00 fe (ff), B UTF-32BE with BOM
                throw ParseException("detected 32bit BOM in big endian order, UTF-32BE (with BOM) unsupported");
            }
            else if (start[2] == #00.byte) {
                if (start[3] == #3c.byte) {
                    // 00 00 00 3c, H UTF-32BE without BOM
                    throw ParseException("detected 32bit ASCII-encoded < in big endian order, UTF-32BE (without BOM) unsupported");
                }
                else {
                    // unknown
                    throw ParseException("probably some 32bit encoding (without BOM), unsupported");
                }
            }
            else if (start[2] == #3c.byte) {
                // 00 00 3c (00), J mixed-endian UTF-32 without BOM
                throw ParseException("detected 32bit ASCII-encoded < in unusual order, but UTF-32 (without BOM) unsupported");
            }
            else if (start[2] == #ff.byte) {
                // 00 00 ff (fe), A mixed-endian UTF-32 with BOM
                throw ParseException("detected 32bit BOM in unusual order, but UTF-32 (with BOM) unsupported");
            }
            else {
                throw ParseException("probably some 32bit encoding (without BOM), unsupported");
            }
        }
        else {
            // unknown
            throw ParseException("probably UTF-16BE (without BOM), but without charset declaration in violation to XML spec. UTF-16BE (without BOM) unsupported anyway.");
        }
    }
    else if (start[0] == #ef.byte && start[1] == #bb.byte && start[2] == #bf.byte) {
        // ef bb bf, G UTF-8 with BOM, charset decl unnecessary, but UTF-8 accepted
        return AdHocEncoding.utf8WithBOM;
    }
    else if (start[0] == #4c.byte && start[1] == #6f.byte && start[2] == #a7.byte && start[3] == #94.byte) {
        // 4c 6f a7 94, O EBCDIC
        throw ParseException("detected EBCDIC-encoded XML declaration, but EBCDIC unsupported");
    }
    else {
        // unknown, using UTF-8, no charset decl found, only UTF-8 allowed.
        return AdHocEncoding.other;
    }
}
