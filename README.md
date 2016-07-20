# ceylon-stax
This is a non-validating, optionally namespace-aware XML 1.0 processor.

It aims at conforming to W3C's [Extensible Markup Language (XML) 1.0 (Fifth Edition)]
(http://www.w3.org/TR/2008/REC-xml-20081126/). As of now, it has the restriction that it doesn't support
document type declarations
(`<!DOCTYPE ...>`) yet, which for example means you only can use the 5 predefined entities
`&amp;`, `&lt;`, `&gt;`, `&apos;`, and `&quot;`.

Namespace support is according to the W3C's [Namespaces in XML 1.0 (Third Edition)]
(http://www.w3.org/TR/2009/REC-xml-names-20091208/).

## Usage
It defines an Iterator-based API for applications to fetch events similar to StAX, but more object oriented.

This might illustrate the usage a bit:
```ceylon

shared void test2()
{
    String xml = "<!-- a test --><ns0:test attr='val' xmlns:ns0='http://madstax.dlkw.de'>some text</ns0:test>";
    value xmlBuf = utf8.encodeBuffer(xml).sequence();
    value r = XMLEventReader(true, xmlBuf);
    while (!is Finished x = r.next()) {
        if (is ParseError x) {
            print(x.msg);
            break;
        }
        
        print(x);

        switch (x)
        case (is StartElement) {
            print("using defined attributes: ``x.attributes``");
        }
        case (is Characters) {
            print("using text content: ``x.text``");
        }
        case (is Comment) {
            print("using comment: ``x.comment``");
        }
        else {
            // ignore all others
        }
    }
}
```