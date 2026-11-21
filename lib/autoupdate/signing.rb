# frozen_string_literal: true

require "securerandom"
require "system_command"
require "utils/output"

module Autoupdate
  # A self-signed code-signing certificate made on this Mac and kept in the
  # login keychain. macOS ties the app's App Management grant to this
  # certificate, so the grant survives rebuilds of the app. See
  # ARCHITECTURE.md, D40.
  module Signing
    extend SystemCommand::Mixin
    extend Utils::Output::Mixin

    module_function

    NAME = "brew-autoupdate local signing"
    # `codesign` refuses an expired certificate, and a new one means granting
    # App Management again.
    VALIDITY_DAYS = 3650

    # The certificate's SHA-1, which `codesign` accepts as the identity.
    # Creates the certificate first if the login keychain does not have one.
    def identity
      create unless existing
      existing || odie("No #{NAME} certificate in #{login_keychain}.")
    end

    def delete
      security "delete-identity", "-c", NAME, login_keychain if existing
    end

    def existing
      output = security("find-identity", "-p", "codesigning", login_keychain).stdout
      output[/^\s*\d+\) (\h{40}) "#{Regexp.escape(NAME)}"/o, 1]
    end

    def login_keychain
      security("login-keychain").stdout.strip.delete('"')
    end

    def create
      # Only protects the temporary `.p12` file, which is deleted afterwards.
      password = SecureRandom.hex(32)

      Dir.mktmpdir do |dir|
        dir = Pathname(dir)
        system_command! "/usr/bin/openssl", args: [
          "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", VALIDITY_DAYS.to_s,
          "-subj", "/CN=#{NAME}",
          "-addext", "basicConstraints=critical,CA:false",
          "-addext", "keyUsage=critical,digitalSignature",
          "-addext", "extendedKeyUsage=critical,codeSigning",
          "-keyout", dir/"key.pem", "-out", dir/"certificate.pem"
        ], print_stderr: false
        # `security import` only reads PKCS#12 files made with these legacy
        # algorithms, which macOS's LibreSSL `openssl` supports.
        system_command! "/usr/bin/openssl", args: [
          "pkcs12", "-export", "-name", NAME,
          "-inkey", dir/"key.pem", "-in", dir/"certificate.pem", "-out", dir/"identity.p12",
          "-passout", "pass:#{password}",
          "-macalg", "sha1", "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES"
        ]
        security "import", dir/"identity.p12", "-k", login_keychain, "-P", password, "-T", "/usr/bin/codesign"
      end

      opoo <<~EOS
        Created a code-signing certificate named "#{NAME}"
        in your login keychain, for the app `brew autoupdate` builds.
        When `codesign` first uses it, macOS asks for your login password;
        choose "Always Allow" to sign later builds without asking again.
        After that, any program running as you can sign code with it
        through `codesign`.
        `brew autoupdate delete` removes it.
      EOS
    end

    def security(*args)
      system_command! "/usr/bin/security", args:, print_stderr: false
    end
  end
end
