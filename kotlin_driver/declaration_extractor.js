
const { log } = require("console");
const { sign } = require("crypto");
const fs = require("fs");
var HTMLParser = require('node-html-parser');

const COMMON = "./docs/kotlin - Kotlin Programming Language.html"

const OUT = "./declarations.txt";

class FunctionDeclarationParser {
    constructor(signature) {
        this.code = signature.querySelectorAll("code")[0];
        this.parts = this.code.childNodes;
        this.i = 0;
        this.parameters = [];
    }

    get query() {
        this.skip();

        this.tryParseReceiverAndName();

        this.parseParameters();

        this.parseReturnType();

        let result = ""
        if (this.parameters.length > 0) {
            result += this.parameters.join(", ");
        } else {
            result = "Unit"
        }

        result = "(" + result + ")"

        if (this.returnType) {
            result += " -> " + this.returnType;
        } else {
            result += " -> Unit"
        }

        if (result.includes(":")) {
            result += "IGNOREME";
        }
        return this.name + ": " + result;
    }

    next() {
        let next
        do {
            next = this.parts[this.i++]
        } while (next && !next.classList)
        return next;
    }

    nextName() {
        const next = this.next()
        if (!next) {
            return next;
        }

        return next.innerText
            .replace("&nbsp;", "")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .trim()
    }

    skip() {
        let next = this.parseUntil("fun");
        next = this.nextName();
        if (next == "<") {
            // while (next != ">") {
            //     next = this.next();
            // }
            this.parseUntil(">");
        } else {
            this.i--;
        }
    }

    tryParseReceiverAndName() {
        const parsed = this.parseUntil("(").result;

        const lastIndex = parsed.lastIndexOf(".");
        if (lastIndex == -1) {
            this.name = parsed;
        } else {
            this.addParam(parsed.slice(0, lastIndex))
            this.name = parsed.slice(lastIndex + 1)
        }
    }

    parseParameters() {
        while (true) {
            const hasParameters = this.parseUntil(":", ")");
            if (!hasParameters.yesStop) {
                break;
            }

            const parsed = this.parseUntil(")", ",");
            this.addParam(parsed.result);

            if (parsed.yesStop) {
                break;
            }
        }
    }

    addParam(str) {
        this.parameters.push(this.prepareType(str))
    }

    addReturnType(str) {
        this.returnType = this.prepareType(str)
    }

    prepareType(str) {
        let result;
        if (str[str.length - 1] == "?") {
            result = "Optional<" + str.slice(0, str.length - 1) + ">"
        } else {
            result = str
        }

        result = result
            .replace("*", "IGNOREME")
            .replace("?", "IGNOREME")
            .replace("Any", "T");

        if (result.includes("->")) {
            return "(" + result + ")"
        } else {
            return result;
        }
    }

    parseUntil(yesStop, noStop) {
        let result = "";

        let next;
        let balance = 0
        let balance2 = 0
        do {
            next = this.nextName();

            if (balance == 0 && balance2 == 0 && next == yesStop) {
                break;
            }
            if (balance == 0 && balance2 == 0 && next == noStop) {
                break;
            }

            result += next;

            if (next == "(") {
                balance++;
            }
            if (next == ")") {
                balance--;
            }
            if (next == "<") {
                balance++;
            }
            if (next == ">") {
                balance--;
            }
        } while (true)

        return {
            yesStop: next == yesStop,
            result: result,
        };
    }

    parseReturnType() {
        let next = this.nextName();

        if (next == ":") {
            this.addReturnType(this.parseUntil(null).result);
        }
    }
};

// TODO: it replace file content
function dumpDeclrations(path) {
    const htmlData = fs.readFileSync(path);
    const root = HTMLParser.parse(htmlData);

    const declarations = root.querySelectorAll(".api-declarations-list .declarations");
    console.log(declarations.length)

    let result = "";
    for (let i = 0; i < declarations.length; i++) {
        const declaration = declarations[i];
        result += dumpDeclaration(declaration);
    }

    fs.writeFileSync(OUT, result);
}

function dumpDeclaration(element) {
    let result = "";

    const signatures = element.querySelectorAll(".signature");

    signatures.forEach(signature => {
        const keywords = signature.querySelectorAll(".keyword");

        if (isFun(keywords)) {
            let parser = new FunctionDeclarationParser(signature);
            const commaSeparatedGenericParameters = /<.*,.*>/g;
            const query = `${parser.query}\n`;
            if (!query.includes(".") &&
                !query.includes("IGNOREME") &&
                !query.includes("ERROR CLASS") &&
                !query.includes("suspend") &&
                !query.match(commaSeparatedGenericParameters) &&
                !query.includes("Optional") &&
                !query.includes("PrintWriter") &&
                !query.includes("PrintStream")) {
                console.log(query);
                result += query
            }
        }
    });

    return result;
}

function isFun(keywords) {
    let is = false;
    keywords.forEach(keyword_ => {
        const keyword = keyword_.innerText.trim();
        if (keyword == "fun") {
            is = true;
        }
        if (keyword == "interface") {
            is = false;
        }
    });

    return is;
}

dumpDeclrations(COMMON);
