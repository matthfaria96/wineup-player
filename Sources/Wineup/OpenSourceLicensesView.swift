import SwiftUI

/// As licenças do Wineup Player e dos projetos de código aberto que ele usa.
struct OpenSourceLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let license: String
        let text: String
    }

    private static let xiphBSD = """
    Redistribution and use in source and binary forms, with or without \
    modification, are permitted provided that the conditions of the BSD \
    3-Clause License are met: redistributions must retain the copyright notice, \
    this list of conditions and the disclaimer, and the names of the copyright \
    holders may not be used to endorse products without permission. THIS \
    SOFTWARE IS PROVIDED "AS IS", WITHOUT ANY WARRANTY.
    """

    private let entries = [
        Entry(id: "wineup", name: "Wineup Player", license: "GNU General Public License v3.0", text: """
        Copyright (C) 2026 Matheus Faria
        Source code: https://github.com/matthfaria96/wineup-player

        Wineup Player is free software: you can redistribute it and/or modify it under \
        the terms of the GNU General Public License as published by the Free Software \
        Foundation, either version 3 of the License, or (at your option) any later \
        version. It is distributed WITHOUT ANY WARRANTY; without even the implied \
        warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

        Full license text: https://www.gnu.org/licenses/gpl-3.0.html
        """),
        Entry(id: "sfbaudioengine", name: "SFBAudioEngine", license: "MIT License", text: """
        Copyright (c) 2006-2026 Stephen F. Booth <me@sbooth.org>
        Source code: https://github.com/sbooth/SFBAudioEngine

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all \
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
        SOFTWARE.
        """),
        Entry(id: "taglib", name: "TagLib", license: "GNU LGPL v2.1 / Mozilla Public License 1.1", text: """
        Copyright (C) 2002-2026 Scott Wheeler and the TagLib authors
        Source code: https://github.com/taglib/taglib

        TagLib is free software; you can redistribute it and/or modify it under the \
        terms of the GNU Lesser General Public License version 2.1 or the Mozilla \
        Public License version 1.1. It is distributed WITHOUT ANY WARRANTY.
        """),
        Entry(id: "lgpl-libs", name: "libsndfile, mpg123, LAME, Musepack, libtta-cpp", license: "GNU LGPL", text: """
        libsndfile: Copyright (C) Erik de Castro Lopo and contributors
        mpg123: Copyright (C) the mpg123 project
        LAME: Copyright (C) the LAME project
        Musepack: Copyright (C) the Musepack Development Team
        libtta-cpp: Copyright (C) Aleksander Djuric

        These libraries are licensed under the GNU Lesser General Public License and \
        ship as replaceable dynamic frameworks in Contents/Frameworks. Their source \
        code is available from the sbooth/*-binary-xcframework repositories and from \
        the original projects. They are distributed WITHOUT ANY WARRANTY.
        """),
        Entry(id: "xiph", name: "libogg, libvorbis, libFLAC, libopus, libspeex", license: "BSD 3-Clause License", text: """
        Copyright (C) Xiph.Org Foundation and contributors

        """ + xiphBSD),
        Entry(id: "wavpack", name: "WavPack", license: "BSD 3-Clause License", text: """
        Copyright (c) David Bryant

        """ + xiphBSD),
        Entry(id: "mac", name: "Monkey's Audio", license: "BSD 3-Clause License", text: """
        Copyright (c) Matthew T. Ashland

        """ + xiphBSD),
        Entry(id: "dumb", name: "DUMB", license: "DUMB License (permissive)", text: """
        Copyright (C) Ben Davis, Robert J Ohannessian and Julien Cugniere

        DUMB is provided "as is", without any express or implied warranty. Permission \
        is granted to use it for any purpose, including commercial applications, and \
        to alter and redistribute it, provided the origin is not misrepresented and \
        altered versions are plainly marked as such.
        """),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Licenças de código aberto")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("O Wineup Player é software livre e usa os projetos de código aberto abaixo. Cada um mantém sua licença original; textos completos em https://github.com/sbooth/SFBAudioEngine/tree/main/LICENSES")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name).font(.system(size: 13, weight: .semibold))
                            Text(entry.license)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
                                .padding(.top, 6)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 600, height: 520)
    }
}
