load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def is_likely_label(v):
    return v.startswith("@") or \
        v.startswith("//") or \
        v.startswith(":")

def expand_flags(**kwargs):
    return {
        k + (is_likely_label(v) and "_flag" or ""): v
        for k, v in kwargs.items()
    }

def flag_or_string(ctx_attr, name):
    strvalue = getattr(ctx_attr, name)
    flagvalue = getattr(ctx_attr, name + "_flag")
    return flagvalue and flagvalue[BuildSettingInfo].value or strvalue
