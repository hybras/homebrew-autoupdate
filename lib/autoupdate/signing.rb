# frozen_string_literal: true

require "securerandom"
require "system_command"
require "utils/output"

module Autoupdate
  # A self-signed code-signing certificate made on this Mac and kept in its own
  # keychain. macOS ties the app's App Management grant to this certificate,
  # so the grant survives rebuilds of the app. See ARCHITECTURE.md, D40.
  module Signing
    extend SystemCommand::Mixin
    extend Utils::Output::Mixin

    module_function

    NAME = "brew-autoupdate local signing"
    # `codesign` refuses an expired certificate, and a new one means granting
    # App Management again.
    VALIDITY_DAYS = 3650

    def keychain
      Autoupdate::Core.location/"signing.keychain-db"
    end

    def password_file
      Autoupdate::Core.location/"signing.password"
    end

    # The certificate's SHA-1, which `codesign` accepts as the identity.
    # Creates the keychain and certificate first if they do not exist.
    def identity
      create unless keychain.exist?

      security "unlock-keychain", "-p", password_file.read, keychain
      add_to_search_list
      output = security("find-certificate", "-c", NAME, "-Z", keychain).stdout
      output[/^SHA-1 hash: (\h{40})$/, 1] || odie("No #{NAME} certificate in #{keychain}.")
    end

    def delete
      security "delete-keychain", keychain if keychain.exist?
    end

    def create
      password = SecureRandom.hex(32)
      File.open(password_file, File::WRONLY | File::CREAT | File::TRUNC, 0600) { |file| file.write(password) }

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

        security "create-keychain", "-p", password, keychain
        # Without options, the keychain never locks itself while logged in.
        security "set-keychain-settings", keychain
        security "import", dir/"identity.p12", "-k", keychain, "-P", password, "-T", "/usr/bin/codesign"
        # Lets `codesign` use the key without asking for the keychain password.
        security "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain
      end

      opoo <<~EOS
        Created a code-signing certificate for the app `brew autoupdate` builds, in:
          #{keychain}
        The keychain's password is in:
          #{password_file}
        The keychain is on your keychain search list, so `codesign` can use it
        unattended, and so can any program running as you.
        `brew autoupdate delete` removes it.
      EOS
    end

    # `codesign` only finds identities in keychains on the search list.
    def add_to_search_list
      keychains = security("list-keychains", "-d", "user").stdout.lines.map { |line| line.strip.delete('"') }
      return if keychains.include?(keychain.to_s)

      security "list-keychains", "-d", "user", "-s", *keychains, keychain
    end

    def security(*args)
      system_command! "/usr/bin/security", args:, print_stderr: false
    end
  end
end
