module Puppet_X
  module Binford2k
    class NodeEncrypt

      def self.encrypted?(data)
        raise ArgumentError, 'Only strings can be encrypted' unless data.class == String
        # ridiculously faster than a regex
        data.start_with?("-----BEGIN PKCS7-----")
      end

      def self.encrypt(data, destination)
        raise ArgumentError, 'Can only encrypt strings' unless data.class == String
        raise ArgumentError, 'Need a node name to encrypt for' unless destination.class == String

        # encrypt with the CA cert on the CA, and the host cert on compile masters
        if Facter.value(:fqdn) == Puppet.settings[:ca_server]
          certpath = Puppet.settings[:cacert]
          keypath  = Puppet.settings[:cakey]
          destpath = "#{Puppet.settings[:signeddir]}/#{destination}.pem"
          Puppet.debug('node_encrypt: Encrypting as the CA')
        else
          certpath = Puppet.settings[:hostcert]
          keypath  = Puppet.settings[:hostprivkey]
          destpath = "#{Puppet.settings[:certdir]}/#{destination}.pem"
          Puppet.debug('node_encrypt: Encrypting as a compile master')
        end

        cert   = OpenSSL::X509::Certificate.new(File.read(certpath))
        key    = OpenSSL::PKey::RSA.new(File.read(keypath), '')
        target = OpenSSL::X509::Certificate.new(File.read(destpath))

        signed = OpenSSL::PKCS7::sign(cert, key, data, [], OpenSSL::PKCS7::BINARY)
        cipher = OpenSSL::Cipher::new("AES-128-CFB")

        OpenSSL::PKCS7::encrypt([target], signed.to_der, cipher, OpenSSL::PKCS7::BINARY).to_s
      end

      def self.decrypt(data)
        raise ArgumentError, 'Can only decrypt strings' unless data.class == String

        cert   = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
        key    = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]), '')
        source = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:localcacert]))

        store = OpenSSL::X509::Store.new
        store.add_cert(source)

        blob      = OpenSSL::PKCS7.new(data)
        decrypted = blob.decrypt(key, cert)
        verified  = OpenSSL::PKCS7.new(decrypted)

        verified.verify(nil, store, nil, OpenSSL::PKCS7::NOCHAIN)
        verified.data
      end

      # This is just a stupid simple value wrapper class that allows us to store and compare
      # two values, but to not print them out in the generated reports.
      class Value
        attr_accessor :decrypted_value

        def initialize(value)
          if Puppet_X::Binford2k::NodeEncrypt.encrypted? value
            @decrypted_value = Puppet_X::Binford2k::NodeEncrypt.decrypt(value)
          else
            @decrypted_value = value
          end
        end

        def == (another)
          # Puppet does some weird comparisons, so let's just short circuit them all
          return false unless another.class == Puppet_X::Binford2k::NodeEncrypt::Value
          @decrypted_value == another.decrypted_value
        end

        def to_s
          '<<encrypted>>'
        end
      end

    end
  end
end