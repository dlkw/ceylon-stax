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

class ChainingIterator<Element>({Iterator<Element>*} iterators)
    satisfies Iterator<Element>
{
    value iterIter = iterators.iterator();
    variable Iterator<Element>|Finished current = iterIter.next();
    shared actual Element|Finished next()
    {
        if (!is Finished cr = current) {
            if (!is Finished it = cr.next()) {
                return it;
            }
            while (!is Finished ii = iterIter.next()) {
                if (!is Finished it = ii.next()) {
                    current = ii;
                    return it;
                }
            }
            current = finished;
            return finished;
        }
        else {
            return finished;
        }
    }
    
    
}

"for now, take an array. Really should be some generic reader."
shared class XMLEventReader(namespaceAware, {Byte*} arr, Charset? forcedEncoding = null)
        satisfies Iterator<XMLEvent|ParseError>
{
    shared Boolean namespaceAware;
    
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

        AdHocEncoding | ParseError guessedEncoding = guessEncoding(head);
        if (!is AdHocEncoding guessedEncoding) {
            throw AssertionError(guessedEncoding.msg);
        }

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
        newIterator = arr.iterator();
    }
    else {
        value guessResult = guessCharset(arr.iterator());
        charset = guessResult[0];
        newIterator = guessResult[1];
    }
    shared String encoding = charset.name;

    value source = PositionPushbackSource(charset.decode(arr).iterator());
    
    shared Integer offset => source.offset;
    shared Integer line => source.line;
    shared Integer column => source.column;
    
    MutableMap<String, String> internalEntities = HashMap<String, String>();
    internalEntities.putAll(predefinedEntities);
    internalEntities.put("ga", "aha<joi>mama</joi> ");
    
    Stack<PositionPushbackSource> entityRefSource = LinkedList<PositionPushbackSource>();
    
    variable State state = State.beforeProlog;
    
    Queue<XMLEvent> parsedEvents = LinkedList<XMLEvent>();

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
                        return StartDocument.absent;
                    }
                    else {
                        c1 = c0;
                    }
                    
                    if (c1 == '<') {
                        state = State.prologLt;
                    }
                    else {
                        return ParseError("text content before root element or wrong encoding (detected ``charset``)");
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
            case (State.prologQuest) {
                switch (it = checkWithPushbackOnFalse("xml"))
                case (finished) {
                    return ParseError("EOF in XML declaration");
                }
                case (false) {
                    state = State.prologPI;
                }
                case (true) {
                    value res = gatherWhitespace();
                    value c = res[1];
                    if (is Finished c) {
                        return ParseError("EOF in XML declaration");
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
                        if (is ParseError startDocument) {
                            return startDocument;
                        }
                        state = State.noXmlDecl;
                        return startDocument;
                    }
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
                        
                        if (namespaceAware) {
                            value nsBindingDeclsAndAttribs = determineNsBindingDeclsAndAttribs(rr[0]);
                            parsedEvents.offer(EndElement(nameResult[0], true));
                            return StartElement(nameResult[0], null, null, true, nsBindingDeclsAndAttribs[1], nsBindingDeclsAndAttribs[0]);
                        }
                        else {
                            parsedEvents.offer(EndElement(nameResult[0], true));
                            return StartElement(nameResult[0], null, null, true, rr[0].map((attrib) => Attribute(attrib.key, attrib.item)));
                        }
                    }
                }
                else if (c1 == '>') {
                    state = State.content;
                    if (namespaceAware) {
                        value nsBindingDeclsAndAttribs = determineNsBindingDeclsAndAttribs(rr[0]);
                        elementPath.push(ElementInfo(nameResult[0]));
                        return StartElement(nameResult[0], null, null, false, nsBindingDeclsAndAttribs[1], nsBindingDeclsAndAttribs[0]);
                    }
                    else {
                        elementPath.push(ElementInfo(nameResult[0]));
                        return StartElement(nameResult[0], null, null, false, rr[0].map((attrib) => Attribute(attrib.key, attrib.item)));
                    }
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
    
    [String, Character]|ParseError gatherVersionDecimal() {
        value sb = StringBuilder();
        while (true) {
            value c = nextChar();
            if (is Finished c) {
                return ParseError("EOF in XML version number");
            }
            if ('0' <= c <= '9') {
                sb.appendCharacter(c);
            }
            else {
                if (sb.empty) {
                    return ParseError("non-digit in XML version number decimal place");
                }
                else {
                    return [sb.string, c];
                }
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
    
    StartDocument|ParseError readXmlDeclaration()
    {
        value versionName = check("version");
        switch (versionName)
        case (finished) {
            return ParseError("EOF in XML declaration");
        }
        case (false) {
            return ParseError("version must be specified in XML declaration");
        }
        case (true) {
            if (is ParseError err = checkAttrEq()) {
                return err;
            }
        }
        value ws = nextChar();
        if (is Finished ws) {
            return ParseError("EOF in XML declaration");
        }
        Character qExpected;
        if (isXmlWhitespace(ws)) {
            value wsResult1 = gatherWhitespace(ws);
            if (!is Finished it1 = wsResult1[1]) {
                qExpected = it1;
            }
            else {
                return ParseError("EOF after attribute name");
            }
        }
        else {
            qExpected = ws;
        }
        if (qExpected != '"' && qExpected != '\'') {
            return ParseError("invalid attribute value delimiter in XML declaration");
        }
        
        value ck = check("1.");
        String version;
        switch (ck)
        case (finished) {
            return ParseError("EOF in XML version");
        }
        case (false) {
            return ParseError("XML version must begin with \"1.\"");
        }
        case (true) {
            value versionDecimal = gatherVersionDecimal();
            if (is ParseError versionDecimal) {
                return versionDecimal;
            }
            if (versionDecimal[1] != qExpected) {
                return ParseError("non-decimal in XML version decimal place");
            }
            version = "1." + versionDecimal[0];
        }
        
        
        
        
        
        value [ws2, c] = gatherWhitespace();
        if (is Finished c) {
            return ParseError("EOF in XML declaration");
        }
        
        Character cnext;
        String? encoding;
        if (c == 'e') {
            value enc = check("ncoding");
            
            value eqRes = checkAttrEq();
            if (is ParseError eqRes) {
                return eqRes;
            }
            
            value ws3 = nextChar();
            if (is Finished ws3) {
                return ParseError("EOF in XML declaration");
            }
            Character qExpected2;
            if (isXmlWhitespace(ws3)) {
                value wsResult1 = gatherWhitespace(ws3);
                if (!is Finished it1 = wsResult1[1]) {
                    qExpected2 = it1;
                }
                else {
                    return ParseError("EOF after attribute name");
                }
            }
            else {
                qExpected2 = ws3;
            }
            value encValue = readXmlDeclEncodingValue(qExpected2);
            if (is ParseError encValue) {
                return encValue;
            }
            encoding = encValue;

            value [ws4, c2] = gatherWhitespace();
            if (is Finished c2) {
                return ParseError("EOF in XML declaration");
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

            value eqRes = checkAttrEq();
            if (is ParseError eqRes) {
                return eqRes;
            }
            
            value ws3 = nextChar();
            if (is Finished ws3) {
                return ParseError("EOF in XML declaration");
            }
            Character qExpected2;
            if (isXmlWhitespace(ws3)) {
                value wsResult1 = gatherWhitespace(ws3);
                if (!is Finished it1 = wsResult1[1]) {
                    qExpected2 = it1;
                }
                else {
                    return ParseError("EOF after attribute name");
                }
            }
            else {
                qExpected2 = ws3;
            }
            value staValue = readYesNoValue(qExpected2);
            if (is ParseError staValue) {
                return staValue;
            }
            standalone = staValue;
            
            value [ws4, c2] = gatherWhitespace();
            if (is Finished c2) {
                return ParseError("EOF in XML declaration");
            }
            cnext2 = c2;
        }
        else {
            standalone = null;
            cnext2 = cnext;
        }

        if (cnext2 != '?') {
            return ParseError("invalid attr in XML declaration");
        }
        value c3 = nextChar();
        if (is Finished c3) {
            return ParseError("EOF in XML declaration");
        }
        if (c3 != '>') {
            return ParseError("invalid XML declaration");
        }

        return StartDocument.present(version, encoding, standalone);
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
        
        if (is ParseError eq = checkAttrEq(nameResult[1])) {
            return eq;
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
    
    ParseError? checkAttrEq(Character? first = null)
    {
        Character c;
        if (exists first) {
            c = first;
        }
        else {
            value cc = nextChar();
            if (is Finished cc) {
                return ParseError("EOF after attribute name");
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
                return ParseError("EOF after attribute name");
            }
        }
        else {
            eqExpected = c;
        }
        
        if (eqExpected != '=') {
            return ParseError("missing = sign after attribute name");
        }
        return null;
    }
    
    String|ParseError readAttributeValue(Character first)
    {
        if (first != '\'' && first != '"') {
            return ParseError("invalid attribute value delimiter");
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
    
    String|ParseError readXmlDeclEncodingValue(Character first)
    {
        if (first != '\'' && first != '"') {
            return ParseError("invalid attribute value delimiter");
        }
        value sb = StringBuilder();

        // first character
        value c0 = nextChar();
        if (is Finished c0) {
            return ParseError("EOF in attribute value");
        }
        if (c0 == first) {
            return sb.string;
        }
        if ('a' <= c0 <= 'z' || 'A' <= c0 <= 'Z') {
            sb.appendCharacter(c0);
        }
        else {
            return ParseError("invalid character in attribute value");
        }

        while (true) {
            value c = nextChar();
            if (is Finished c) {
                return ParseError("EOF in attribute value");
            }
            if (c == first) {
                return sb.string;
            }
            if ('a' <= c <= 'z' || 'A' <= c <= 'Z' || '0' <= c <= '9' || c == '-' || c == '_' || c == '.') {
                sb.appendCharacter(c);
            }
            else {
                return ParseError("invalid character in encoding attribute value");
            }
        }
    }
    
    Boolean|ParseError readYesNoValue(Character first)
    {
        if (first != '\'' && first != '"') {
            return ParseError("invalid attribute value delimiter");
        }
        value sb = StringBuilder();
        
        while (true) {
            value c = nextChar();
            if (is Finished c) {
                return ParseError("EOF in attribute value");
            }
            if (c == first) {
                if (sb.string == "yes") {
                    return true;
                }
                else if (sb.string == "no") {
                    return false;
                }
                else {
                    return ParseError("standalone value must be yes or no");
                }
            }
            if (c in "yesno") {
                sb.appendCharacter(c);
            }
            else {
                return ParseError("standalone value must be yes or no");
            }
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

[Map<String, String>, List<Attribute>] determineNsBindingDeclsAndAttribs(Map<String, String> attribsKeyValue)
{
    [MutableMap<String, String>, MutableList<Attribute>] res = [HashMap<String, String>(), ArrayList<Attribute>()];
    attribsKeyValue.each((entry)
    {
        Null|ParseError bind(MapMutator<String, String> decls, String key, String item)
        {
            if (key.any((c)=>c == ':')) {
                return ParseError("prefix may not contain a colon (:)");
            }
            if (item == namespace_xml && key != "xml") {
                return ParseError("namespace ``namespace_xml`` may be bound to prefix xml only");
            }
            else if (item == namespace_xmlns) {
                return ParseError("namespace ``namespace_xmlns`` may not be bound to any prefix");
            }
            decls.put(key, item);
            return null;
        }
        
       if (entry.key.startsWith("xmlns")) {
            if (!entry.key.longerThan(5)) {
                if (is ParseError it = bind(res[0], "", entry.item)) {
                    return it;
                }
            }
            else {
                if (exists colon = entry.key[5], colon == ':') {
                    value prefix = entry.key.spanFrom(6);
                    if (prefix.empty) {
                        return ParseError("namespace prefix to define missing");
                    }
                    else {
                        if (exists it = res[0].get(prefix)) {
                            return ParseError("namespace prefix defined twice in element");
                        }
                        if (prefix.startsWith("xml")) {
                            if (!prefix.longerThan(3)) {
                                if (entry.item != namespace_xml) {
                                    return ParseError("prefix xml may be bound to ``namespace_xml`` only");
                                }
                                else {
                                    if (is ParseError it = bind(res[0], prefix, entry.item)) {
                                        return it;
                                    }
                                }
                            }
                            else {
                                if (prefix.equals("xmlns")) {
                                    return ParseError("prefix xmlns may not be declared");
                                }
                            }
                        }
                        else {
                            if (is ParseError it = bind(res[0], prefix, entry.item)) {
                                return it;
                            }
                        }
                    }
                }
                else {
                    // attribute starting with xmnls#, where # is a Character, but not a colon
                    // TODO attribute namespace prefix stuff
                    if (entry.key.any((c)=>c == ':')) {
                        return ParseError("attribute name may not contain colon (:)");
                    }
                    res[1].add(Attribute(entry.key, entry.item));
                }
            }
       }
       else {
           // TODO attribute namespace prefix stuff
           if (entry.key.any((c)=>c == ':')) {
               return ParseError("attribute name may not contain colon (:)");
           }
           res[1].add(Attribute(entry.key, entry.item));
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

AdHocEncoding|ParseError guessEncoding(Byte[4] start)
{
    if (start[0] == #3c.byte) {
        if (start[1] == #3f.byte) {
            // 3c 3f, N UTF-8 without BOM, charset decl unnecessary, but may be any ASCII-valued 8bit encoding
            return AdHocEncoding.utf8WithoutBOM;
        }
        else if (start[1] == #00.byte) {
            if (start[2] == #3f.byte) {
                // 3c 00 3f, M UTF-16LE without BOM
                return ParseError("detected 16bit ASCII-encoded <? in little endian order, but UTF-16LE (without BOM) unsupported");
            }
            else if (start[2] == #00.byte) {
                // 3c 00 00, I maybe UTF-32LE without BOM
                return ParseError("detected 32bit ASCII-encoded < in little endian order, but UTF-32LE (without BOM) unsupported");
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
            return ParseError("detected 32bit BOM in unusual order, but UTF-32 (with BOM) unsupported");
        }
        else {
            // fe ff ## ##, E UTF-16BE with BOM, charset decl unnecessary
            return AdHocEncoding.utf16beWithBOM;
        }
    }
    else if (start[0] == #ff.byte && start[1] == #fe.byte) {
        if (start[2] == #00.byte && start[3] == #00.byte) {
            // ff fe 00 00, C UTF-32LE with BOM
            return ParseError("detected 32bit BOM in little endian order, UTF-32LE (with BOM) unsupported");
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
                return ParseError("detected 16bit ASCII-encoded <? in big endian order, but UTF-16BE (without BOM) unsupported");
            }
            else if (start[3] == #00.byte) {
                // 00 3c 00 00, K mixed-endian UTF-32 without BOM
                return ParseError("detected 32bit ASCII-encoded < in unusual order, but UTF-32 (without BOM) unsupported");
            }
            else {
                // 00 3c 00 ##, probably UTF-16BE (without BOM), but without charset decl., which is an error
                return ParseError("probably UTF-16BE (without BOM), but without charset declaration in violation to XML spec. UTF-16BE (without BOM) unsupported anyway.");
            }
        }
        else if (start[1] == #00.byte) {
            if (start[2] == #fe.byte) {
                // 00 00 fe (ff), B UTF-32BE with BOM
                return ParseError("detected 32bit BOM in big endian order, UTF-32BE (with BOM) unsupported");
            }
            else if (start[2] == #00.byte) {
                if (start[3] == #3c.byte) {
                    // 00 00 00 3c, H UTF-32BE without BOM
                    return ParseError("detected 32bit ASCII-encoded < in big endian order, UTF-32BE (without BOM) unsupported");
                }
                else {
                    // unknown
                    return ParseError("probably some 32bit encoding (without BOM), unsupported");
                }
            }
            else if (start[2] == #3c.byte) {
                // 00 00 3c (00), J mixed-endian UTF-32 without BOM
                return ParseError("detected 32bit ASCII-encoded < in unusual order, but UTF-32 (without BOM) unsupported");
            }
            else if (start[2] == #ff.byte) {
                // 00 00 ff (fe), A mixed-endian UTF-32 with BOM
                return ParseError("detected 32bit BOM in unusual order, but UTF-32 (with BOM) unsupported");
            }
            else {
                return ParseError("probably some 32bit encoding (without BOM), unsupported");
            }
        }
        else {
            // unknown
            return ParseError("probably UTF-16BE (without BOM), but without charset declaration in violation to XML spec. UTF-16BE (without BOM) unsupported anyway.");
        }
    }
    else if (start[0] == #ef.byte && start[1] == #bb.byte && start[2] == #bf.byte) {
        // ef bb bf, G UTF-8 with BOM, charset decl unnecessary, but UTF-8 accepted
        return AdHocEncoding.utf8WithBOM;
    }
    else if (start[0] == #4c.byte && start[1] == #6f.byte && start[2] == #a7.byte && start[3] == #94.byte) {
        // 4c 6f a7 94, O EBCDIC
        return ParseError("detected EBCDIC-encoded XML declaration, but EBCDIC unsupported");
    }
    else {
        // unknown, using UTF-8, no charset decl found, only UTF-8 allowed.
        return AdHocEncoding.other;
    }
}

shared abstract class XMLEvent()
        of StartDocument | StartElement | EndElement | Characters | EntityReference | ProcessingInstruction | Comment | EndDocument | DTD | Attribute | Namespace
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

shared class StartElement(localName, prefix = null, namespaceName = null, Boolean emptyElementTag = false, attributes = empty, namespaceDeclarations = emptyMap)
        extends XMLEvent()
{
    shared String localName;
    shared String? prefix;
    shared String? namespaceName;
    shared {Attribute*} attributes;
    shared Map<String, String> namespaceDeclarations;
    
    shared actual String string
    {
        value sb = StringBuilder();
        sb.append("Start element \"");
        if (exists prefix) {
            sb.append(prefix).appendCharacter(':');
        }
        sb.append(localName);
        if (exists namespaceName) {
            sb.appendCharacter('{').append(namespaceName).appendCharacter('}');
        }
        sb.appendCharacter('"');
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
