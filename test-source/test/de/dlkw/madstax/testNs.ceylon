import de.dlkw.madstax {
    ParseError,
    XMLEventReader,
    XMLEvent,
    StartElement
}
import ceylon.test {
    test
}
import ceylon.buffer.charset {
    utf8
}

test
shared void colonInPrefixIsForbidden()
{
    String xml = "<element xmlns:a:a=\"http://a.com/a\"/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is ParseError it = r.next());
}

test
shared void xmlPrefixRedeclarationOk()
{
    String xml = "<element xmlns:xml=\"http://www.w3.org/XML/1998/namespace\"/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is XMLEvent it = r.next());
}

test
shared void xmlPrefixRedeclarationWrong()
{
    String xml = "<element xmlns:xml=\"http://a.com/a\"/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is ParseError it = r.next());
    print(it.msg);
}

test
shared void xmlnsPrefixRedeclarationWrong1()
{
    String xml = "<element xmlns:xmlns=\"http://www.w3.org/2000/xmlns/\"/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is ParseError it = r.next());
    print(it.msg);
}

test
shared void xmlnsPrefixRedeclarationWrong2()
{
    String xml = "<element xmlns:xmlns=\"http://a.com/a\"/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is ParseError it = r.next());
    print(it.msg);
}

test
shared void xmlNamespaceNoDefaultBindable()
{
    String xml = "<element xmlns=\"http://www.w3.org/XML/1998/namespace\"/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is ParseError it = r.next());
    print(it.msg);
}

test
shared void xmlnsNamespaceNoDefaultBindable()
{
    String xml = "<element xmlns=\"http://www.w3.org/2000/xmlns/\"/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is ParseError it = r.next());
    print(it.msg);
}

test
shared void xmlNamespaceNoPrefixBindable()
{
    String xml = "<element xmlns:a=\"http://www.w3.org/XML/1998/namespace\"/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is ParseError it = r.next());
    print(it.msg);
}

test
shared void xmlnsNamespaceNoPrefixBindable()
{
    String xml = "<element xmlns:a=\"http://www.w3.org/2000/xmlns/\"/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is ParseError it = r.next());
    print(it.msg);
}

test
shared void xmlnsNoPrefixTwice()
{
    String xml = "<element xmlns:a=\"http://dlkw.de\" xmlns:a=\"http://dlkw.de\"/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is ParseError it = r.next());
    print(it.msg);
}

test
shared void xmlnsNoEmptyPrefix()
{
    String xml = "<element xmlns:a=''/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is ParseError it = r.next());
    print(it.msg);
}

test
shared void declareDefaultNoNamespace()
{
    String xml = "<element xmlns=''/>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    r.next();
    assert (is StartElement it = r.next());
}
