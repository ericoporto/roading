AGSScriptModule        ?=  // JSON Parser Module Script

// internal methods
#define EASYJSON_TOKENGUESS 64

// Allocates a fresh unused token from the token pool.
JsonToken *_json_alloc_token(JsonParser *parser, JsonToken *tokens[], int num_tokens) {
  JsonToken *tok;
  if (parser.toknext >= num_tokens) {
    return null;
  }
  tok = tokens[parser.toknext];
  parser.toknext = parser.toknext+1;
  tok.end = -1;
  tok.start = -1;
  tok.size = 0;
  tok.parent = -1;
  return tok;
}

// Fills token type and boundaries.
void _json_fill_token(JsonToken *token, JsonTokenType type, int start, int end) {
  token.type = type;
  token.start = start;
  token.end = end;
  token.size = 0;
}

// part of _json_parse_primitive.
int _parse_found(int start, JsonParser *parser, String json_string, int len, JsonToken *tokens[], int num_tokens){
  JsonToken *token;
  if (tokens == null) {
    parser.pos--;
    return 0;
  }
  token = _json_alloc_token(parser, tokens, num_tokens);
  if (token == null) {
    parser.pos = start;
    return eJSON_Error_InsuficientTokens;
  }
  _json_fill_token(token, eJSON_Tok_PRIMITIVE, start, parser.pos);

  token.parent = parser.toksuper;
  parser.pos--;
  return 0;
}

// Fills next available token with JSON primitive.
int _json_parse_primitive(JsonParser *parser, String json_string, int len, JsonToken *tokens[], int num_tokens) {
  JsonToken *token;
  int start;

  start = parser.pos;

  for (; parser.pos < len && json_string.Chars[parser.pos] != 0; parser.pos++) {
    switch (json_string.Chars[parser.pos]) {

    /* In strict mode primitive must be followed by "," or "}" or "]" */
//    case ':':
    case 20: /* '\t' */
    case 18: /* '\r' */
    case 14: /* '\n' */
    case ' ':
    case ',':
    case ']':
    case '}':
      return _parse_found(start, parser, json_string, len, tokens, num_tokens);
    default:
                   /* to quiet a warning from gcc*/
      break;
    }
    if (json_string.Chars[parser.pos] < 32 || json_string.Chars[parser.pos] >= 127) {
      parser.pos = start;
      return eJSON_Error_InvalidCharacter;
    }
  }
  return _parse_found(start, parser, json_string, len, tokens, num_tokens);
}

// Fills next token with JSON string.
int _json_parse_string(JsonParser *parser, String json_string, int len, JsonToken *tokens[], int num_tokens) {
  JsonToken *token;

  int start = parser.pos;

  parser.pos++;

  /* Skip starting quote */
  for (; parser.pos < len && json_string.Chars[parser.pos] != 0; parser.pos++) {
    char c = json_string.Chars[parser.pos];

    /* Quote: end of string */
    if (c == '"') {
      if (tokens == null) {
        return 0;
      }
      token = _json_alloc_token(parser, tokens, num_tokens);
      if (token == null) {
        parser.pos = start;
        return eJSON_Error_InsuficientTokens;
      }
      _json_fill_token(token, eJSON_Tok_STRING, start + 1, parser.pos);
      token.parent = parser.toksuper;
      return 0;
    }

    /* Backslash: Quoted symbol expected */
    if (c == 92 && parser.pos + 1 < len) {
      parser.pos++;
      switch (json_string.Chars[parser.pos]) {
      /* Allowed escaped symbols */
      case '"':
      case '/':
      case 92:
      case 'b':
      case 'f':
      case 'r':
      case 'n':
      case 't':
        break;
      /* Allows escaped symbol \uXXXX */
      case 'u':
        parser.pos++;
        for (int i = 0; i < 4 && parser.pos < len && json_string.Chars[parser.pos] != 0; i++) {
          /* If it isn't a hex character we have an error */
          if (!((json_string.Chars[parser.pos] >= 48 && json_string.Chars[parser.pos] <= 57) ||   /* 0-9 */
                (json_string.Chars[parser.pos] >= 65 && json_string.Chars[parser.pos] <= 70) ||   /* A-F */
                (json_string.Chars[parser.pos] >= 97 && json_string.Chars[parser.pos] <= 102))) { /* a-f */
            parser.pos = start;
            return eJSON_Error_InvalidCharacter;
          }
          parser.pos++;
        }
        parser.pos--;
        break;
      /* Unexpected symbol */
      default:
        parser.pos = start;
        return eJSON_Error_InvalidCharacter;
      }
    }
  }
  parser.pos = start;
  return eJSON_Error_Partial;
}

////  PUBLIC METHODS

// helper to create array of tokens
static JsonToken* [] JsonToken::NewArray(int count)
{
  JsonToken* tks[];
  tks = new JsonToken[count];
  for(int i=0; i<count; i++) tks[i] = new JsonToken;
  return tks;
}

String JsonToken::ToString(String json_string)
{
  return json_string.Substring(this.start, this.end-this.start);
}

String get_TypeAsString(this JsonToken*)
{
  switch(this.type)
  {
    case eJSON_Tok_OBJECT: return "Object"; break;
    case eJSON_Tok_ARRAY: return "Array"; break;
    case eJSON_Tok_PRIMITIVE: return "Primitive"; break;
    case eJSON_Tok_STRING: return "String"; break;
    case eJSON_Tok_UNDEFINED: return "Undefined"; break;
  }
  return "Error";
}


// Parse JSON string and fill tokens.
int JsonParser::Parse(String json_string, JsonToken *tokens[], int num_tokens) {
  int r;
  JsonToken *t;
  JsonToken *token;
  int count = this.toknext;
  int len = json_string.Length;

  if(!this._IsNotReset) {
    this.toksuper = -1;
    this.toknext = 0;
    this.pos = 0;
    this._IsNotReset = true;
  }

  for (; this.pos < len && json_string.Chars[this.pos] != 0; this.pos++) {
    char c;
    JsonTokenType type;

    c = json_string.Chars[this.pos];

    switch (c) {
    case '{':
    case '[':
      count++;
      if (tokens == null) {
        break;
      }
      token = _json_alloc_token(this, tokens, num_tokens);
      if (token == null) {
        return eJSON_Error_InsuficientTokens;
      }
      if (this.toksuper != -1) {
        t = tokens[this.toksuper];

        /* In strict mode an object or array can't become a key */
        if (t.type == eJSON_Tok_OBJECT) {
          return eJSON_Error_InvalidCharacter;
        }

        t.size++;
        token.parent = this.toksuper;
      }
      if(c == '{') token.type = eJSON_Tok_OBJECT;
      else token.type = eJSON_Tok_ARRAY;
      token.start = this.pos;
      this.toksuper = this.toknext - 1;
      break;
    case '}':
    case ']':
      if (tokens == null) {
        break;
      }

      if(c == '}') type = eJSON_Tok_OBJECT;
      else type = eJSON_Tok_ARRAY;

      if (this.toknext < 1) {
        return eJSON_Error_InvalidCharacter;
      }
      token = tokens[this.toknext - 1];
      for (;;) {
        if (token.start != -1 && token.end == -1) {
          if (token.type != type) {
            return eJSON_Error_InvalidCharacter;
          }
          token.end = this.pos + 1;
          this.toksuper = token.parent;
          break;
        }
        if (token.parent == -1) {
          if (token.type != type || this.toksuper == -1) {
            return eJSON_Error_InvalidCharacter;
          }
          break;
        }
        token = tokens[token.parent];
      }
      break;
    case '"': /* '\"' */
      r = _json_parse_string(this, json_string, len, tokens, num_tokens);
      if (r < 0) {
        return r;
      }
      count++;
      if (this.toksuper != -1 && tokens != null) {
        tokens[this.toksuper].size++;
      }
      break;
    case 20: /* '\t' */
    case 18: /* '\r' */
    case 14: /* '\n' */
    case ' ':
      break;
    case ':':
      this.toksuper = this.toknext - 1;
      break;
    case ',':
      if (tokens != null && this.toksuper != -1 &&
          tokens[this.toksuper].type != eJSON_Tok_ARRAY &&
          tokens[this.toksuper].type != eJSON_Tok_OBJECT) {

        this.toksuper = tokens[this.toksuper].parent;

      }
      break;

    /* In strict mode primitives are: numbers and booleans */
    case '-':
    case '0':
    case '1':
    case '2':
    case '3':
    case '4':
    case '5':
    case '6':
    case '7':
    case '8':
    case '9':
    case 't': /* true  */
    case 'f': /* false */
    case 'n': /* null  */
      /* And they must not be keys of the object */
      if (tokens != null && this.toksuper != -1) {
        t = null;
        t = tokens[this.toksuper];
        if (t.type == eJSON_Tok_OBJECT ||
            (t.type == eJSON_Tok_STRING && t.size != 0)) {
          return eJSON_Error_InvalidCharacter;
        }
      }

      r = _json_parse_primitive(this, json_string, len, tokens, num_tokens);
      if (r < 0) {
        return r;
      }
      count++;
      if (this.toksuper != -1 && tokens != null) {
        tokens[this.toksuper].size++;
      }
      break;

    default: /* Unexpected char in strict mode */
      return eJSON_Error_InvalidCharacter;
    }

  }

  if (tokens != null) {
    for (int i = this.toknext - 1; i >= 0; i--) {
      /* Unmatched opened object or array */
      if (tokens[i].start != -1 && tokens[i].end == -1) {
        return eJSON_Error_Partial;
      }
    }
  }

  return count;
}

void JsonParser::Reset()
{
  this._IsNotReset = false;
}

void MiniJsonParser::Init(String json_string)
{
  int ret;
  this._JsonString = json_string;

  JsonParser* parser = new JsonParser;
  int n = EASYJSON_TOKENGUESS;
  this._Tokens = JsonToken.NewArray(n);
  ret = parser.Parse(this._JsonString, this._Tokens , n);

  while(ret == eJSON_Error_InsuficientTokens)
  {
    n = n * 2;
    this._Tokens = JsonToken.NewArray(n);
    ret = parser.Parse(this._JsonString, this._Tokens , n);
  }

  if(ret == eJSON_Error_InvalidCharacter)
    AbortGame("FastJsonParser::Init: ERROR Invalid character in JSON String.");

  if(ret == eJSON_Error_Partial)
    AbortGame("FastJsonParser::Init: ERROR JSON String is incomplete.");

  this._TokenCount = ret;

  this._next_itok = 0;
  this._next_ichildren = 1;
  this._next_State = eJP_State_START;
  this._stk_children_idx = 0;
}

protected String MiniJsonParser::_print_children()
{
  String str = "";
  for(int i=0; i<=this._stk_children_idx; i++) {
      str = str.Append(String.Format("%d { %d }",i, this._stk_children[i]));
    if(i == this._stk_children_idx -1) str=str.Append(" <");
    str = str.Append("\n");
  }
  return str;
}


protected void MiniJsonParser::_stk_children_push(int value, JsonTokenType type) {
  this._stk_children[this._stk_children_idx] = value;
  this._stk_type[this._stk_children_idx] = type;
  this._stk_children_idx++;
}
protected  int MiniJsonParser::_stk_children_pop() {
  int retval = this._stk_children[this._stk_children_idx];
  this._stk_children_idx--;
  return retval;
}
protected int MiniJsonParser::_stk_children_head_get() {
  return this._stk_children[this._stk_children_idx-1];
}
protected JsonTokenType MiniJsonParser::_stk_type_head_get() {
  return this._stk_type[this._stk_children_idx-1];
}
protected void MiniJsonParser::_stk_children_head_decr() {
  this._stk_children[this._stk_children_idx-1] -= 1;
}

protected String MiniJsonParser::_print_keyidx()
{
  String str = "";
  for(int i=0; i<=this._stk_keyidx_idx; i++) {
    if(String.IsNullOrEmpty(this._stk_keyidx[i])) {
      str = str.Append(String.Format("%d {    }",i));
    } else {
      str = str.Append(String.Format("%d { %s }",i, this._stk_keyidx[i]));
    }
    if(i == this._stk_keyidx_idx-1) str=str.Append(" <");
    str = str.Append("\n");
  }
  return str;
}

protected void MiniJsonParser::_stk_keyidx_push(String keyidx) {
  this._stk_keyidx[this._stk_keyidx_idx] = keyidx;
  this._stk_keyidx_idx++;

}
protected void MiniJsonParser::_stk_keyidx_pop() {
  this._stk_keyidx_idx--;
}
protected void MiniJsonParser::_stk_keyidx_increment() {
  String str = this._stk_keyidx[this._stk_keyidx_idx-1];
  this._stk_keyidx[this._stk_keyidx_idx-1] = String.Format("%d", str.AsInt+1);
}
protected String MiniJsonParser::_stk_keyidx_tostring() {
  String ret = "";
  for(int i = 0; i < this._stk_keyidx_idx; i++) {
    if(i == this._stk_keyidx_idx - 1) ret = ret.Append(this._stk_keyidx[i]);
    else ret = ret.Append(this._stk_keyidx[i].Append("."));
  }
  return ret;
}

bool MiniJsonParser::NextToken()
{
  this._itok = this._next_itok;
  this._ichildren = this._next_ichildren;

  while ((this._State == eJP_State_VALUE || this._State == eJP_State_ARRVALUE) && this._stk_children_idx != 0 && this._stk_children_head_get() == 0) {
    this._stk_children_pop();
    if(this._stk_children_idx == 0) break;
    if(this._stk_type_head_get() == eJSON_Tok_ARRAY) {
      this._next_State = eJP_State_ARRVALUE;
    } else {
      this._stk_keyidx_pop();
    }
    if(this._stk_type_head_get() == eJSON_Tok_OBJECT) {
      this._next_State = eJP_State_KEY;
    }
  }

  this._State = this._next_State;

  // if there are no children left we have finished all tokens
  // this is the right way to finish parsing
  if(this._ichildren == 0) { return false; }
  if(this._itok > this._TokenCount) AbortGame("FastJsonParser::NextToken: ERROR tried to reach inexistent token");

  this._t = this._Tokens[this._itok];

  this._ichildren += this._t.size;

  switch(this._State)
  {
    case eJP_State_START:
      if(this._t.type == eJSON_Tok_OBJECT)
      {
        this._next_State = eJP_State_KEY;
        this._stk_children_push(this._t.size, this._t.type);
      }
      else if(this._t.type == eJSON_Tok_ARRAY)
      {
        this._next_State = eJP_State_ARRVALUE;
        this._stk_children_push(this._t.size, this._t.type);
        this._stk_keyidx_push("-1");
      }
      break;

    case eJP_State_KEY:
      if(this._t.type != eJSON_Tok_STRING)
        AbortGame("FastJsonParser::NextToken: ERROR Object keys must be strings.");

      this._stk_children_head_decr();
      this._stk_children_push(this._t.size, this._t.type);
      this._stk_keyidx_push(this._t.ToString(this._JsonString));
      this._next_State = eJP_State_VALUE;

      break;

    case eJP_State_VALUE:
      this._stk_children_head_decr();
      if (this._t.type == eJSON_Tok_STRING || this._t.type == eJSON_Tok_PRIMITIVE)
      {
        // it's a real value
        this._next_State = eJP_State_KEY;
      }
      else if(this._t.type == eJSON_Tok_ARRAY)
      {
        // our values are array
        this._next_State = eJP_State_ARRVALUE;
        this._stk_children_push(this._t.size, this._t.type);
        this._stk_keyidx_push("-1");
      }
      else if(this._t.type == eJSON_Tok_OBJECT)
      {
        // our value is another object
        this._next_State = eJP_State_KEY;
        this._stk_children_push(this._t.size, this._t.type);
      }

      break;

    case eJP_State_ARRVALUE:
      this._stk_children_head_decr();
      this._stk_keyidx_increment();
      if (this._t.type == eJSON_Tok_STRING || this._t.type == eJSON_Tok_PRIMITIVE)
      {
        // it's a real value
        this._next_State = eJP_State_ARRVALUE;
      }
      else if(this._t.type == eJSON_Tok_ARRAY)
      {
        // our values are array
        this._next_State = eJP_State_ARRVALUE;
        this._stk_children_push(this._t.size, this._t.type);
        this._stk_keyidx_push("-1");
      }
      else if(this._t.type == eJSON_Tok_OBJECT)
      {
        // our value is another object
        this._next_State = eJP_State_KEY;
        this._stk_children_push(this._t.size, this._t.type);
      }

      break;
    case eJP_State_STOP:

      break;
  }

  this._next_itok = this._itok + 1;
  this._next_ichildren = this._ichildren - 1;
  return true;
}


String get_CurrentTokenAsString(this MiniJsonParser*)    { return this._t.ToString(this._JsonString); }
JsonTokenType get_CurrentTokenType(this MiniJsonParser*) { return this._t.type; }
int get_CurrentTokenSize(this MiniJsonParser*) { return this._t.size; }
MiniJsonParserState get_CurrentState(this MiniJsonParser*)      { return this._State; }
String get_CurrentFullKey(this MiniJsonParser*) { return this._stk_keyidx_tostring();}
bool get_CurrentTokenIsLeaf(this MiniJsonParser*) { 
  return ((this._State == eJP_State_VALUE || this._State == eJP_State_ARRVALUE) && 
          (this._t.type == eJSON_Tok_PRIMITIVE || this._t.type == eJSON_Tok_STRING));
}
 ?  // JSON Parser Module Header
//       jsonparser 0.1.0

 /// JSON type identifier.
 enum JsonTokenType {
  eJSON_Tok_UNDEFINED = 0,
  eJSON_Tok_OBJECT,    /* Object */
  eJSON_Tok_ARRAY,     /* Array */
  eJSON_Tok_STRING,    /* String */
  eJSON_Tok_PRIMITIVE,   /* ther primitive: number, boolean (true/false) or null */
  eJSON_TokMAX
};

/// Negative numbers after parsing can be either error below
enum JsonError {
  eJSON_Error_InsuficientTokens = -1, /* Not enough tokens were provided */
  eJSON_Error_InvalidCharacter = -2,  /* Invalid character inside JSON string */
  eJSON_Error_Partial = -3            /* The string is not a full JSON packet, more bytes expected */
};

/// JSON token description.
managed struct JsonToken {
  /// Type: object, array, string etc.
  JsonTokenType type;
  /// start position in JSON data string
  int start;
  /// end position in JSON data string
  int end;
  /// 0 if it's a leaf value, 1 or bigger if it's a key or object/array
  int size;
  /// if it's a child, position of the parent in the token array
  int parent;
  /// pass the json_string that was parsed and generated this token to recover the string this token refers to
  import String ToString(String json_string);
  /// Utility function for debugging
  import readonly attribute String TypeAsString;
  /// Helper to ease Token Array creation. Ex: JsonToken* t[] = JsonToken.NewArray(token_count);
  import static JsonToken* [] NewArray(int count); // $AUTOCOMPLETESTATICONLY$
};

/// JSON parser, stores the current position in the string being parsed.
managed struct JsonParser {
  /// offset in the JSON string
  int pos;
  /// next token to allocate
  int toknext;
  /// superior token node, e.g. parent object or array
  int toksuper;
  /// Parses a JSON data string into and array of tokens, each describing a single JSON object. Negative return is a JsonError, otherwise it's the number of used tokens.
  import int Parse(String json_string, JsonToken *tokens[], int num_tokens);
  /// Marks the parser for reset, useful if you want to use it again with a different file. Reset only actually happens when Parse is called.
  import void Reset();
  protected bool _IsNotReset;
};

enum MiniJsonParserState {
  eJP_State_START = 0,
  eJP_State_KEY,
  eJP_State_VALUE,
  eJP_State_ARRVALUE,
  eJP_State_STOP,
  eJP_StateMAX
};

struct MiniJsonParser {
  /// Initialize the parser passing a JSON as a string.
  import void Init(String json_string);
  /// Advances to the next token. Returns false if no tokens left.
  import bool NextToken();
  /// The current token content, as a String.
  import readonly attribute String CurrentTokenAsString;
  /// The current token type.
  import readonly attribute JsonTokenType CurrentTokenType;
  /// The current token size, 0 if it's a leaf value, 1 or bigger if it's a key or object/array.
  import readonly attribute int CurrentTokenSize;
  /// The current state of our mini parser. Helps understanding the JSON tokens we got when parsing.
  import readonly attribute MiniJsonParserState CurrentState;
  /// Gets the current dot separated key.
  import readonly attribute String CurrentFullKey;
  /// Checks if the state and key type currently are a leaf. True if it's, usually leafs are the interesting tokens we want when parsing.
  import readonly attribute bool CurrentTokenIsLeaf;

  // a bunch of protected things to hide the complexity of simplicity
  // these are not accessible to the user
  protected String _JsonString;
  protected MiniJsonParserState _State;
  protected int _TokenCount;
  protected JsonToken* _Tokens[];
  protected int _itok;
  protected int _ichildren;

  import protected String _print_children();
  protected int _stk_children_idx;
  protected int _stk_children[32];
  protected int _stk_type[32];
  protected String _stk_keyidx[32];
  import protected void _stk_children_push(int value, JsonTokenType type);
  import protected JsonTokenType _stk_type_head_get();
  import protected int _stk_children_pop();
  import protected int _stk_children_head_get();
  import protected void _stk_children_head_decr();

  import protected String _print_keyidx();
  protected int _stk_keyidx_idx;
  import protected void _stk_keyidx_push(String keyidx);
  import protected void _stk_keyidx_pop();
  import protected void _stk_keyidx_increment();
  import protected String _stk_keyidx_tostring();

  protected int _next_itok;
  protected int _next_ichildren;
  protected int _next_State;
  protected JsonToken* _t;
};
 ??Cc        ej??