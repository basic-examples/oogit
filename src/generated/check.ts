import typia from "typia";
import { Oogit } from "../types/Oogit";
export const check = (() => { const _io0 = (input: any): boolean => "string" === typeof input.repository && "string" === typeof input.path && "string" === typeof input.branch && "string" === typeof input.commit; return (input: any): input is Oogit => "object" === typeof input && null !== input && _io0(input); })();
