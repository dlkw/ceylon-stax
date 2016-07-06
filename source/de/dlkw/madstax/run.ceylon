import ceylon.buffer.charset {
    utf8
}
import ceylon.collection {
    LinkedList,
    Queue,
    Stack,
    ArrayList,
    HashMap,
    MutableMap
}
shared class ParseError(shared String msg){}

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

class ElementInfo(name)
{
    shared String name;
}

"for now, take an array. Really should be some generic reader."
shared class XMLEventReader({Byte*} arr)
        satisfies Iterator<XMLEvent|ParseError>
{
    value source = PositionPushbackSource(utf8.decode(arr).iterator());
    
    shared Integer offset => source.offset;
    shared Integer line => source.line;
    shared Integer column => source.column;
    
    MutableMap<String, String> internalEntities = HashMap<String, String>();
    internalEntities.putAll(predefinedEntities);
    internalEntities.put("ga", "aha<joi>mama</joi> ");
    
    Stack<PositionPushbackSource> entityRefSource = LinkedList<PositionPushbackSource>();
    
    variable State state = State.beforeProlog;
    
    Queue<XMLEvent> parsedEvents = LinkedList<XMLEvent>();
    
    StringBuilder sb1 = StringBuilder();
    
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
    
    shared actual XMLEvent|ParseError|Finished next()
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
                        return StartDocument(defaultXmlVersion, defaultXmlEncoding, false);
                    }
                    else {
                        c1 = c0;
                    }
                    
                    if (c1 == '<') {
                        state = State.prologLt;
                    }
                    else {
                        return ParseError("text content before root element");
                    }
                }
                else {
                    return ParseError("no root element");
                }
            }
            case (State.prologLt) {
                if (!is Finished c = source.nextChar()) {
                    if (c == '!') {
                        state = State.prologExclam;
                        return StartDocument(defaultXmlVersion, defaultXmlEncoding, false);
                    }
                    else if (c == '?') {
                        state = State.prologQuest;
                    }
                    else if (isNameStartChar(c)) {
                        source.pushbackChar(c);
                        state = State.rootEl;
                        return StartDocument(defaultXmlVersion, defaultXmlEncoding, false);
                    }
                    else {
                        return ParseError("invalid name start character");
                    }
                }
                else {
                    return ParseError("EOF while reading prolog");
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
                            return ParseError("EOF after tag opening");
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
                        return ParseError("text content before root element");
                    }
                }
                else {
                    return ParseError("no root element");
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
                    return ParseError("no root element");
                }
            }
            case (State.prologExclam) {
                if (!is Finished c = source.nextChar()) {
                    if (c == '-') {
                        value commentResult = readComment("-");
                        if (is ParseError commentResult) {
                            return commentResult;
                        }
                        state = State.noXmlDecl;
                        return Comment(commentResult);
                    }
                    else if (c == 'D') {
                        return ParseError("DOCTYPE not supported yet");
                    }
                    else {
                        return ParseError("invalid tag beginning <!");
                    }
                }
                else {
                    return ParseError("EOF while reading comment/doctype in prolog");
                }
            }
            case (State.prologPI) {
                value pi = readProcessingInstruction();
                if (is ParseError pi) {
                    return pi;
                }
                state = State.noXmlDecl;
                return ProcessingInstruction(pi[0], pi[1]);
            }
            case (State.rootEl) {
                state = State.element;
            }
            case (State.element) {
                value nameResult = gatherName();
                if (is ParseError nameResult) {
                    return nameResult;
                }

                value c0 = nameResult[1];
                
                value rr = gatherAttributes(c0);
                if (is ParseError rr) {
                    return rr;
                }
                
                Character c1 = rr[1];

                if (c1 == '/') {
                    switch (it = check(">"))
                    case (finished) {
                        return ParseError("EOF in close empty tag");
                    }
                    case (false) {
                        return ParseError("invalid empty tag close");
                    }
                    case (true) {
                        if (is Null parentEl = elementPath.top) {
                            state = State.afterRoot;
                        }
                        else {
                            state = State.content;
                        }
                        parsedEvents.offer(EndElement(nameResult[0], true));
                        return StartElement(nameResult[0], true, rr[0].map((attrib) => Attribute(attrib.key, attrib.item)));
                    }
                }
                else if (c1 == '>') {
                    state = State.content;
                    elementPath.push(ElementInfo(nameResult[0]));
                    return StartElement(nameResult[0], false, rr[0].map((attrib) => Attribute(attrib.key, attrib.item)));
                }
                else {
                    return ParseError("invalid character in start element tag");
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
                    if (is ParseError contentResult) {
                        return contentResult;
                    }
                    sb.append(contentResult[0]);
                    whitespace &&= contentResult[2];

                    if (contentResult[1] == '<') {
                        value c = nextChar();
                        if (is Finished c) {
                            return ParseError("EOF in element start");
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
                            return ParseError("EOF in content");
                        }
                        if (c0 == '#') {
                            value cr = resolveCharacterReference(nextChar);
                            if (is ParseError cr) {
                                return cr;
                            }
                            whitespace &&= isXmlWhitespace(cr);
                            sb.appendCharacter(cr);
                        }
                        else {
                            value ref = gatherName(c0);
                            if (is ParseError ref) {
                                return ref;
                            }
                            if (ref[1] != ';') {
                                return ParseError("entity reference does not finish with ;");
                            }
                            
                            value replacementText = internalEntities[ref[0]];
                            if (exists replacementText) {
                                entityRefSource.push(PositionPushbackSource(replacementText.iterator()));
                            }
                            else {
                                return ParseError("entity not defined");
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
                    return ParseError("EOF in start comment/CDATA section");
                }
                if (c1 == '-') {
                    value commentResult = readComment("-");
                    if (is ParseError commentResult) {
                        return commentResult;
                    }
                    state = State.content;
                    return Comment(commentResult);
                }
                else if (c1 == '[') {
                    value res = check("CDATA[");
                    switch (res)
                    case (finished | false) {
                        return ParseError("invalid CDATA section start");
                    }
                    case (true) {
                        value cdataResult = gatherCData();
                        if (is ParseError cdataResult) {
                            return cdataResult;
                        }
                        state = State.content;
                        return Characters(cdataResult[0], cdataResult[1], false); 
                    }
                }
                else {
                    return ParseError("invalid start comment/CDATA section");
                }
            }
            case (State.contentPI) {
                value pi = readProcessingInstruction();
                if (is ParseError pi) {
                    return pi;
                }
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
                    return ParseError("EOF in tag");
                }
            }
            case (State.endElementTag) {
                value nameResult = gatherName();
                if (is ParseError nameResult) {
                    return nameResult;
                }
                
                value c0 = nameResult[1];
                
                Character c1;
                if (isXmlWhitespace(c0)) {
                    value [ws, c] = gatherWhitespace(c0);
                    if (is Finished c) {
                        return ParseError("EOF in element tag");
                    }
                    c1 = c;
                }
                else {
                    c1 = c0;
                }
                
                if (c1 != '>') {
                    return ParseError("Invalid end element tag");
                }
                
                //FIXME check name match
                value expectedName = elementPath.pop();
                assert (exists expectedName);
                
                if (expectedName.name != nameResult[0]) {
                    return ParseError("end tag not matching start tag");
                }
                
                if (exists it = elementPath.top) {
                    state = State.content;
                }
                else {
                    state = State.afterRoot;
                }
                return EndElement(nameResult[0]);
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
                                if (is ParseError commentResult) {
                                    return commentResult;
                                }
                                return Comment(commentResult);
                            }
                            else if (c1 == '?') {
                                value pi = readProcessingInstruction();
                                if (is ParseError pi) {
                                    return pi;
                                }
                                return ProcessingInstruction(pi[0], pi[1]);
                            }
                            else {
                                return ParseError("multiple root elements");
                            }
                        }
                        else {
                            return ParseError("EOF in comment/processing instruction after root element");
                        }
                    }
                    else {
                        return ParseError("invalid text after root element");
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

    [String, Character]|ParseError gatherName(Character? first = null)
    {
        value firstChar = first else nextChar();
        if (is Finished firstChar) {
            return ParseError("EOF in Name");
        }
        if (!isNameStartChar(firstChar)) {
            return ParseError("Invalid name starting character '``firstChar``'");
        }
        StringBuilder sb = StringBuilder().appendCharacter(firstChar);
        while (true) {
            value c = nextChar();
            if (is Finished c) {
                return ParseError("EOF in Name");
            }
            if (isNameChar(c)) {
                sb.appendCharacter(c);
            }
            else {
                return [sb.string, c];
            }
        }
    }
    
    String|ParseError gatherComment()
    {
        value sb = StringBuilder();
        while (true) {
            value c0 = nextChar();
            if (is Finished c0) {
                return ParseError("EOF in comment");
            }
            if (c0 == '-') {
                value c1 = nextChar();
                if (is Finished c1) {
                    return ParseError("EOF in comment");
                }
                if (c1 == '-') {
                    value c2 = nextChar();
                    if (is Finished c2) {
                        return ParseError("EOF in comment");
                    }
                    if (c2 == '>') {
                        return sb.string;
                    }
                    return ParseError("-- in comment");
                }
                if (isChar(c1)) {
                    sb.appendCharacter(c0).appendCharacter(c1);
                }
                else {
                    return ParseError("invalid character in comment");
                }
            }
            if (isChar(c0)) {
                sb.appendCharacter(c0);
            }
            else {
                return ParseError("invalid character in comment");
            }
        }
    }
    
    [String, Boolean]|ParseError gatherCData()
    {
        variable Boolean isWhitespace = true;
        value sb = StringBuilder();
        while (true) {
            value c0 = nextChar();
            if (is Finished c0) {
                return ParseError("EOF in comment");
            }
            if (c0 == ']') {
                value c1 = nextChar();
                if (is Finished c1) {
                    return ParseError("EOF in comment");
                }
                if (c1 == ']') {
                    value c2 = nextChar();
                    if (is Finished c2) {
                        return ParseError("EOF in comment");
                    }
                    if (c2 == '>') {
                        return [sb.string, isWhitespace];
                    }
                    return ParseError("-- in comment");
                }
                if (isChar(c1)) {
                    isWhitespace &&= isXmlWhitespace(c1);
                    sb.appendCharacter(c0).appendCharacter(c1);
                }
                else {
                    return ParseError("invalid character in comment");
                }
            }
            if (isChar(c0)) {
                isWhitespace &&= isXmlWhitespace(c0);
                sb.appendCharacter(c0);
            }
            else {
                return ParseError("invalid character in comment");
            }
        }
    }
    
    [String, Character, Boolean, Boolean]|ParseError gatherTextContent()
    {
        variable Boolean isWhitespace = true;
        value sb = StringBuilder();
        while (true) {
            value c0 = nextChar();
            if (is Finished c0) {
                return ParseError("EOF in text content");
            }
            
            if (c0 == '<' || c0 == '&') {
                return [sb.string, c0, isWhitespace, false];
            }
            
            if (!isChar(c0)) {
                return ParseError("invalid character in text content");
            }
            
            if (c0 == ']') {
                value c1 = nextChar();
                if (is Finished c1) {
                    return ParseError("EOF in text content");
                }
                if (c1 == ']') {
                    value c2 = nextChar();
                    if (is Finished c2) {
                        return ParseError("EOF in text content");
                    }
                    if (c2 == '>') {
                        /* FIXME this is a hack, text content until here should be returned as
                         * Characters and the the next event fetch result in this error.
                         */
                        return ParseError("]]> in text content not allowed");
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
    
    String|ParseError gatherUntilQuestGt(Character first)
    {
        variable Character|Finished crs = first;
        StringBuilder sb = StringBuilder();
        while (true) {
            value c = crs;
            if (is Finished c) {
                return ParseError("EOF in PI or XMLDecl");
            }
            if (c == '?') {
                value c2 = nextChar();
                if (is Finished c2) {
                    return ParseError("EOF in PI or XMLDecl");
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
    
    [String, String]|ParseError readProcessingInstruction()
    {
        if (!is Finished c = nextChar()) {
            value targetRes = gatherName(c);
            if (is ParseError targetRes) {
                return targetRes;
            }
            String target = targetRes[0];
            if (target == "xml") {
                return ParseError("forbidden processing instruction target \"xml\"");
            }
            Character c0 = targetRes[1];
            if (!isXmlWhitespace(c0)) {
                return ParseError("whitespace expected after processing instruction target");
            }
            value wsRes = gatherWhitespace(c0);
            value c1 = wsRes[1];
            if (is Finished c1) {
                return ParseError("EOF in processing instruction");
            }
            value instruction = gatherUntilQuestGt(c1);
            if (is ParseError instruction) {
                return instruction;
            }
            return [target, instruction];
        }
        else {
            return ParseError("EOF while reading processing instruction");
        }
    }
    
    
    String|ParseError readComment(String startStringToCheck)
    {
        switch (it = check(startStringToCheck))
        case (finished) {
            return ParseError("EOF while reading comment");
        }
        case (false) {
            return ParseError("missing second - in comment start");
        }
        case (true) {
            value commentResult = gatherComment();
            if (is ParseError commentResult) {
                return commentResult;
            }
            else {
                return commentResult;
            }
        }
    }

    [Map<String,String>, Character]|ParseError gatherAttributes(Character first)
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
                    return ParseError("EOF in start element tag");
                }
                if (res == '>' || res == '/') {
                    return [result, res];
                }
                value attribute = readAttribute(res);
                if (is ParseError attribute) {
                    return attribute;
                }
                if (exists prev = result.put(attribute.key, attribute.item)) {
                    return ParseError("duplicate attribute key");
                }
                value c0 = nextChar();
                if (is Finished c0) {
                    return ParseError("EOF in start element tag");
                }
                c = c0;
            }
            else {
                return ParseError("need whitespace before attribute");
            }
        }
    }
    
    <String->String>|ParseError readAttribute(Character first)
    {
        value nameResult = gatherName(first);
        if (is ParseError nameResult) {
            return nameResult;
        }
        value attributeName = nameResult[0];
        Character eqExpected;
        if (isXmlWhitespace(nameResult[1])) {
            value wsResult1 = gatherWhitespace(nameResult[1]);
            if (!is Finished it1 = wsResult1[1]) {
                eqExpected = it1;
            }
            else {
                return ParseError("EOF after attribute name");
            }
        }
        else {
            eqExpected = nameResult[1];
        }

        if (eqExpected != '=') {
            return ParseError("missing = sign after attribute name");
        }
        value wsResult2 = gatherWhitespace();
        if (!is Finished it2 = wsResult2[1]) {
            value attributeValue = readAttributeValue(it2);
            if (is ParseError attributeValue) {
                return attributeValue;
            }
            else {
                return attributeName->attributeValue;
            }
        }
        else {
            return ParseError("EOF while expecting attribute value");
        }
    }
    
    String|ParseError readAttributeValue(Character first)
    {
        if (first != '\'' && first != '"') {
            return ParseError("invalid attribute value deliminter");
        }
        value sb = StringBuilder();
        while (true) {
            value c = nextChar();
            if (is Finished c) {
                return ParseError("EOF in attribute value");
            }
            if (c == first) {
                return normalizeAttributeValue(sb.string, true);
            }
            // & is allowed to accept references.
            if (c == '<' || !isChar(c)) {
                return ParseError("invalid character in attribute value");
            }
            sb.appendCharacter(c);
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

shared abstract class XMLEvent()
        of StartDocument | StartElement | EndElement | Characters | EntityReference | ProcessingInstruction | Comment | EndDocument | DTD | Attribute | Namespace
{
    
}

shared class StartDocument(shared String version, shared String encoding, Boolean xmlDeclPresent)
        extends XMLEvent()
{
    shared actual String string => "Start document XML ``version`` encoding ``encoding``";
}

shared class StartElement(shared String localName, Boolean emptyElementTag = false, {Attribute*} attributes = empty)
        extends XMLEvent()
{
    shared actual String string
    {
        value sb = StringBuilder();
        sb.append("Start element \"``localName``\"");
        for (a in attributes) {
            sb.appendCharacter('\n').append(a.string);
        }
        return sb.string;
    }
}

shared class EndElement(shared String localName, Boolean emptyElementTag = false)
        extends XMLEvent()
{
    shared actual String string => "End element \"``localName``\"";
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
{}

shared class DTD()
        extends XMLEvent()
{}

shared class Attribute(shared String name, shared String valu)
        extends XMLEvent()
{
    shared actual String string => "\tAttribute ->``name``->``valu``";
}

shared class Namespace()
        extends XMLEvent()
{}
