# Copyright 2020 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

def _k8s_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            name = ctx.label.name,
            kubectl = ctx.attr.kubectl,
            kustomize = ctx.attr.kustomize,
        ),
        platform_common.TemplateVariableInfo({
            "KUBECTL": ctx.attr.kubectl.files.to_list()[0].path,
            "KUSTOMIZE": ctx.attr.kustomize.files.to_list()[0].path,
        }),
    ]

k8s_toolchain = rule(
    _k8s_toolchain_impl,
    attrs = {
        "kubectl": attr.label(
            doc = "Target to a downloaded kubectl binary.",
            mandatory = True,
        ),
        "kustomize": attr.label(
            doc = "Target to a downloaded kustomize binary.",
            mandatory = True,
        ),
    },
    doc = "Defines a k8s toolchain",
    provides = [platform_common.ToolchainInfo, platform_common.TemplateVariableInfo],
)

_K8S_BUILD_FILE = """
load("@com_adobe_rules_gitops//toolchains:k8s_toolchain.bzl", "k8s_toolchain")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "kubectl",
    srcs = glob(["kubectl.{os_arch}"]),
)

sh_binary(
    name = "kustomize",
    srcs = ["kustomize.{os_arch}"],
    visibility = ["//visibility:public"],
)

k8s_toolchain(
    name = "toolchain",
    kubectl = ":kubectl",
    kustomize = ":kustomize",
)
"""

def _k8s_repository_rule_impl(ctx):
    os_arch = ctx.attr.os_arch
    kubectl_url, kubectl_sha256 = ctx.attr.kubectl_url, ctx.attr.kubectl_sha256
    kustomize_url, kustomize_sha256 = ctx.attr.kustomize_url, ctx.attr.kustomize_sha256
    ctx.file(
        "BUILD",
        content = _K8S_BUILD_FILE.format(os_arch = os_arch),
        executable = False,
    )
    ctx.report_progress("Downloading kubectl")
    ctx.download(
        url = [kubectl_url],
        sha256 = kubectl_sha256,
        output = "kubectl.{os_arch}".format(os_arch = os_arch),
        executable = True,
    )
    ctx.report_progress("Downloading kustomize")
    ctx.download_and_extract(
        url = [kustomize_url],
        sha256 = kustomize_sha256,
        output = ".",
    )
    # tarball has a kustomize file that we need to symlink to be able to declare a sh_binary
    ctx.symlink("kustomize", "kustomize.{os_arch}".format(os_arch = os_arch))

k8s_repository_rule = repository_rule(
    implementation = _k8s_repository_rule_impl,
    attrs = {
        "os_arch": attr.string(mandatory=True),
        "kubectl_url": attr.string(mandatory=True),
        "kubectl_sha256": attr.string(mandatory=True),
        "kustomize_url": attr.string(mandatory=True),
        "kustomize_sha256": attr.string(mandatory=True),
    }
)

def _k8s_toolchains_impl(repository_ctx):
    content = """
load("@com_adobe_rules_gitops//toolchains:k8s_toolchain.bzl", "k8s_repository_rule")

package(default_visibility = ["//visibility:public"])
    """
    for name, platforms in repository_ctx.attr.toolchains.items():
        content += """
toolchain(
    name = "k8s_{name}_toolchain",
    exec_compatible_with = [
        {platforms},
    ],
    target_compatible_with = [
        {platforms},
    ],
    toolchain = "@k8s_{name}_toolchain_repo//:toolchain",
    toolchain_type = "@com_adobe_rules_gitops//toolchains:toolchain_type",
)
""".format(
    name = name,
    platforms = platforms,
)

    repository_ctx.file(
        "BUILD",
        content = content,
        executable = False,
    )

_k8s_toolchains = repository_rule(
    implementation = _k8s_toolchains_impl,
    attrs = {
        "toolchains": attr.string_dict(mandatory=True),
    },
    doc = "Repository rule to configure repository rules for each toolchain"
)

_PLATFORMS = {
    "linux_amd64": [
        "@bazel_tools//platforms:linux",
        "@bazel_tools//platforms:x86_64",
    ],
    "darwin_amd64": [
        "@bazel_tools//platforms:osx",
        "@bazel_tools//platforms:x86_64",
    ],
}

_VERSIONS_KUBECTL = {
    "linux_amd64": {
        "url": "https://dl.k8s.io/release/v1.21.0/bin/linux/amd64/kubectl",
        "sha256": "9f74f2fa7ee32ad07e17211725992248470310ca1988214518806b39b1dad9f0",
    },
    "darwin_amd64": {
        "url": "https://dl.k8s.io/release/v1.21.0/bin/darwin/amd64/kubectl",
        "sha256": "f9dcc271590486dcbde481a65e89fbda0f79d71c59b78093a418aa35c980c41b",
    },
}

_VERSIONS_KUSTOMIZE = {
    "linux_amd64": {
        "url": "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv3.5.5/kustomize_v3.5.5_linux_amd64.tar.gz",
        "sha256": "23306e0c0fb24f5a9fea4c3b794bef39211c580e4cbaee9e21b9891cb52e73e7",
    },
    "darwin_amd64": {
        "url": "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv3.5.5/kustomize_v3.5.5_darwin_amd64.tar.gz",
        "sha256": "5e286dc6e02c850c389aa3c1f5fc4ff5d70f064e480d49e804f209c717c462bd",
    },
}

def k8s_register_toolchains(
    kubectl_versions = _VERSIONS_KUBECTL,
    kustomize_versions = _VERSIONS_KUSTOMIZE,
    platforms = _PLATFORMS,
):
    """Register the appropriate toolchains for kubectl.

    We use _k8s_toolchains as a repository rule to declare the toolchains as we
    cannot declare toolchains in a WORKSPACE, and those toolchains will reference
    the k8s_repository_rule that will download the appropriate files.

    """
    args = {}
    toolchains = dict([(k, ",".join(['"%s"' % k for k in p])) for k, p in platforms.items()])

    for os_name, values in kubectl_versions.items():
        args[os_name] = {
            "kubectl_url": values["url"],
            "kubectl_sha256": values["sha256"],
        }
    for os_name, values in kustomize_versions.items():
        args[os_name]["kustomize_url"] = values["url"]
        args[os_name]["kustomize_sha256"] = values["sha256"]

    for name, values in args.items():
        k8s_repository_rule(
            # add the _repo suffix to match what the toolchain will reference
            name = "k8s_"+name+"_toolchain_repo",
            os_arch = name,
            **values,
        )

    _k8s_toolchains(
        name = "k8s_toolchains",
        toolchains = toolchains,
    )

    native.register_toolchains(*["@k8s_toolchains//:k8s_"+k+"_toolchain" for k in args.keys()])