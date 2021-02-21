#include <ecl/ecl.h>
#include "tree-sitter.h"
extern void init(cl_object);

char *package = "SOFTWARE-EVOLUTION-LIBRARY/SOFTWARE/TREE-SITTER";

void start(){
  int argc = 0;
  char** argv = (char*[]){""};

  cl_boot(argc, argv);
  ecl_init_module(NULL, init);
}

void stop(){
  cl_shutdown();
}

cl_object eval(char *source){
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
    return ecl_make_keyword("ERROR");
  } ECL_CATCH_ALL_END;
}

cl_object language_symbol(language language){
  switch(language){
  case JAVASCRIPT: return ecl_make_symbol("JAVASCRIPT-AST", package);
  case PYTHON: return ecl_make_symbol("PYTHON-AST", package);
  case C: return ecl_make_symbol("C-AST", package);
  case CPP: return ecl_make_symbol("CPP-AST", package);
  }
}

cl_object convert(language language, char *source){
  cl_env_ptr env = ecl_process_env();
  ECL_CATCH_ALL_BEGIN(env) {
    /*
     * Code that is protected. Uncaught lisp conditions, THROW,
     * signals such as SIGSEGV and SIGBUS may cause jump to
     * this region.
     */
  return cl_funcall(3, c_string_to_object("convert"),
                    language_symbol(language),
                    ecl_cstring_to_base_string_or_nil(source));
  } ECL_CATCH_ALL_IF_CAUGHT {
    /*
     * If the exception, lisp condition or other control transfer
     * is caught, this code is executed.
     */
    return ecl_make_keyword("ERROR");
  } ECL_CATCH_ALL_END;
}

wchar_t* type(cl_object cl_object){
  return cl_funcall(2, c_string_to_object("type-of"), cl_object)->string.self;
}

/* // Alternate implementation taking a single position offset into the text string.
 * cl_object ast_at_point(cl_object ast, int position){
 *   return cl_car(cl_last(1, cl_funcall(3, c_string_to_object("asts-containing-source-location"),
 *                                       ast,
 *                                       position)));
 * }
*/

cl_object ast_at_point(cl_object ast, int line, int column){
  return cl_car(cl_last(1, cl_funcall(3, c_string_to_object("asts-containing-source-location"),
                                      ast,
                                      cl_funcall(6, c_string_to_object("make-instance"),
                                                 ecl_make_symbol("SOURCE-LOCATION", package),
                                                 ecl_make_keyword("LINE"), line,
                                                 ecl_make_keyword("COLUMN"), column))));
}
