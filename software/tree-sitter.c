#include <ecl/ecl.h>
#include <locale.h>
#include <stdio.h>
#include <string.h>
#include "tree-sitter.h"
extern void init(cl_object);

char *package = "SOFTWARE-EVOLUTION-LIBRARY/SOFTWARE/TREE-SITTER";


/* Utility and debug functions. */
size_t last_string_length;

wchar_t* get_string(cl_object cl_object){
  last_string_length = cl_object->string.dim;
  #ifdef DEBUG
  fprintf(stderr, "; Returning string: '%ls'\n", cl_object->string.self);
  #endif
  return cl_object->string.self;
}

size_t get_last_string_length(){
  return last_string_length;
}

wchar_t* to_string(cl_object cl_object){
  return get_string(cl_funcall(4, c_string_to_object("format"),
                               c_string_to_object("nil"),
                               c_string_to_object("\"~&~S\""),
                               cl_object));
}

short to_short(cl_object cl_object){
  return ecl_to_short(cl_object);
}

void show(cl_object cl_object){
  cl_funcall(4, c_string_to_object("format"),
             c_string_to_object("t"),
             c_string_to_object("\"~&; ~S~%\""),
             cl_object);
}

cl_object eval(char* source){
  cl_env_ptr env = ecl_process_env();
  ECL_CATCH_ALL_BEGIN(env) {
    /*
     * Code that is protected. Uncaught lisp conditions, THROW,
     * signals such as SIGSEGV and SIGBUS may cause jump to
     * this region.
     */
    return cl_eval(c_string_to_object(source));
  } ECL_CATCH_ALL_IF_CAUGHT {
    /*
     * If the exception, lisp condition or other control transfer
     * is caught, this code is executed.
     */
    return ECL_NIL;
  } ECL_CATCH_ALL_END;
}

cl_object language_symbol(language language){
  switch(language){
  case JAVASCRIPT: return ecl_make_symbol("JAVASCRIPT-AST", package);
  case PYTHON: return ecl_make_symbol("PYTHON-AST", package);
  case C: return ecl_make_symbol("C-AST", package);
  case CPP: return ecl_make_symbol("CPP-AST", package);
  case UNKNOWN_LANGUAGE: return ecl_make_symbol("UNKNOWN_LANGUAGE", package);
  }
  return ECL_NIL;
}

cl_object car(cl_object list){
  return ecl_car(list);
}

cl_object cdr(cl_object list){
  return ecl_cdr(list);
}

bool null(cl_object object){
  return ecl_eql(object, ECL_NIL);
}

bool eql(cl_object left, cl_object right){
  return ecl_eql(left, right);
}


/* API functions */
void start(){
  int argc = 0;
  char** argv = (char*[]){""};

  setlocale(LC_ALL, "");
  cl_boot(argc, argv);
  ecl_init_module(NULL, init);
}

void stop(){
  cl_shutdown();
}

cl_object convert(language language, char* source){
  cl_env_ptr env = ecl_process_env();
  ECL_CATCH_ALL_BEGIN(env) {
    /*
     * Code that is protected. Uncaught lisp conditions, THROW,
     * signals such as SIGSEGV and SIGBUS may cause jump to
     * this region.
     */
  return cl_funcall(3, c_string_to_object("convert"),
                    language_symbol(language),
                    /* ecl_cstring_to_base_string_or_nil(source)); */
                    ecl_make_constant_base_string(source, strlen(source)));
  } ECL_CATCH_ALL_IF_CAUGHT {
    /*
     * If the exception, lisp condition or other control transfer
     * is caught, this code is executed.
     */
    return ECL_NIL;
  } ECL_CATCH_ALL_END;
}

cl_object get_type(cl_object cl_object){
  return cl_type_of(cl_object);
}

cl_object get_class(cl_object cl_object){
  return cl_funcall(2, c_string_to_object("class-name"), (cl_class_of(cl_object)));
}

wchar_t* symbol_name(cl_object cl_object){
  return to_string(cl_funcall(2, c_string_to_object("symbol-name"), cl_object));
}

/* // Alternate implementation taking a single position offset into the text string.
 * cl_object ast_at_point(cl_object ast, int position){
 *   return cl_car(cl_last(1, cl_funcall(3, c_string_to_object("asts-containing-source-location"),
 *                                       ast,
 *                                       position)));
 * }
*/

cl_object ast_at_point(cl_object ast, int line, int column){
  cl_env_ptr env = ecl_process_env();
  ECL_CATCH_ALL_BEGIN(env) {
    return cl_car(cl_last(1, cl_funcall(3, c_string_to_object("asts-containing-source-location"),
                                        ast,
                                        cl_funcall(6, c_string_to_object("make-instance"),
                                                   ecl_make_symbol("SOURCE-LOCATION", package),
                                                   ecl_make_keyword("LINE"), line,
                                                   ecl_make_keyword("COLUMN"), column))));
  } ECL_CATCH_ALL_IF_CAUGHT {
    return ECL_NIL;
  } ECL_CATCH_ALL_END;
}

wchar_t* source_text(cl_object ast){
  return get_string(cl_funcall(2, c_string_to_object("source-text"), ast));
}

cl_object children(cl_object ast){
  return(cl_funcall(2, c_string_to_object("children"), ast));
}

cl_object child_slots(cl_object ast){
  return cl_funcall(2, c_string_to_object("child-slots"), ast);
}

cl_object slot(cl_object ast, const char* slot_name){
  return ecl_slot_value(ast, slot_name);
}

cl_object parent(cl_object root, cl_object ast){
  return cl_funcall(4, c_string_to_object("get-parent-ast"), root, ast);
}

#define type_check(NAME) if(! null(cl_funcall(3, c_string_to_object("subtypep"), \
                       cl_funcall(2, c_string_to_object("type-of"), ast), \
                       ecl_make_symbol( #NAME "-AST", package)))) \
    return NAME

language ast_language(cl_object ast){
  type_check(PYTHON);
  else type_check(JAVASCRIPT);
  else type_check(C);
  else type_check(CPP);
  else return UNKNOWN_LANGUAGE;
}

type ast_type(cl_object ast){
  type_check(PARSE_ERROR);
  else type_check(CHAR);
  else type_check(NUMBER);
  else type_check(GOTO);
  else type_check(COMPOUND);
  else type_check(CLASS);
  else type_check(CONTROL_FLOW);
  else type_check(IF);
  else type_check(WHILE);
  else type_check(EXPRESSION);
  else type_check(FUNCTION);
  else type_check(BOOLEAN_TRUE);
  else type_check(BOOLEAN_FALSE);
  else type_check(IDENTIFIER);
  else type_check(LAMBDA);
  else type_check(INTEGER);
  else type_check(FLOAT);
  else type_check(STRING);
  else type_check(LOOP);
  else type_check(STATEMENT);
  else type_check(CALL);
  else type_check(UNARY);
  else type_check(BINARY);
  else type_check(RETURN);
  else type_check(VARIABLE_DECLARATION);
  else return UNKNOWN_TYPE;
}

bool subtypep(cl_object ast, char* type_name){
  return ! ecl_eql(ECL_NIL, cl_subtypep(2, ast, ecl_make_symbol(type_name, package)));
}

/* General methods */
cl_object function_asts(cl_object ast){
  return cl_funcall(3, c_string_to_object("remove-if-not"),
                    c_string_to_object("{typep _ 'function-ast}"),
                    ast);
}

wchar_t* function_name(cl_object ast){
  return get_string(cl_funcall(2, c_string_to_object("function-name"), ast));
}

cl_object function_parameters(cl_object ast){
  return cl_funcall(2, c_string_to_object("function-parameters"), ast);
}

cl_object function_body(cl_object ast){
  return cl_funcall(2, c_string_to_object("function-body"), ast);
}

cl_object call_asts(cl_object ast){
  return cl_funcall(3, c_string_to_object("remove-if-not"),
                    c_string_to_object("{typep _ 'call-ast}"),
                    ast);
}

cl_object call_arguments(cl_object ast){
  return cl_funcall(2, c_string_to_object("call-arguments"), ast);
}

cl_object call_module(cl_object ast){
  return cl_funcall(2, c_string_to_object("call-module"), ast);
}

cl_object call_function(cl_object ast){
  return cl_funcall(2, c_string_to_object("call-function"), ast);
}