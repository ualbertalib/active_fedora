require 'spec_helper'

describe ActiveFedora::Datastream do
  let(:parent) { double('inner object', uri: "#{ActiveFedora.fedora.host}#{ActiveFedora.fedora.base_path}/1234", id: '1234', new_record?: true) }
  let(:datastream) { ActiveFedora::Datastream.new(parent, 'abcd') }

  subject { datastream }

  it { should_not be_metadata }

  describe "#behaves_like_io?" do
    subject { datastream.send(:behaves_like_io?, object) }

    context "with a File" do
      let(:object) { File.new __FILE__ }
      it { should be true }
    end

    context "with a Tempfile" do
      after { object.close; object.unlink }
      let(:object) { Tempfile.new('foo') }
      it { should be true }
    end

    context "with a StringIO" do
      let(:object) { StringIO.new('foo') }
      it { should be true }
    end
  end

  describe "to_param" do
    before { allow(subject).to receive(:dsid).and_return('foo.bar') }
    it "should escape dots" do
      expect(subject.to_param).to eq 'foo%2ebar'
    end
  end

  describe "#generate_dsid" do
    let(:parent) { double('inner object', uri: "#{ActiveFedora.fedora.host}#{ActiveFedora.fedora.base_path}/1234", id: '1234',
                          new_record?: true, attached_files: datastreams) }

    subject { ActiveFedora::Datastream.new(parent, nil, prefix: 'FOO') }

    let(:datastreams) { { } }

    it "should set the dsid" do
      expect(subject.dsid).to eq 'FOO1'
    end

    it "should set the uri" do
      expect(subject.uri).to eq "#{ActiveFedora.fedora.host}#{ActiveFedora.fedora.base_path}/1234/FOO1"
    end

    context "when some datastreams exist" do
      let(:datastreams) { {'FOO56' => double} }

      it "should start from the highest existing dsid" do
        expect(subject.dsid).to eq 'FOO57'
      end
    end
  end

  context "content" do
    
    let(:mock_conn) do
      Faraday.new do |builder|
        builder.adapter :test, conn_stubs do |stub|
        end
      end
    end

    let(:mock_client) do
      Ldp::Client.new mock_conn
    end

    let(:conn_stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.head('/fedora/rest/test/1234/abcd') { [200, {'Content-Length' => '9999' }] }
      end
    end

    before do
      allow(subject).to receive(:ldp_connection).and_return(mock_client)
    end

    describe '#persisted_size' do
      it 'should load the datastream size attribute from the fedora repository' do
        expect(subject.size).to eq 9999
      end

      it 'returns nil without making a head request to Ldp::Resource::BinarySource if it is a new record' do
        allow(subject).to receive(:new_record?).and_return(true)
        expect(subject.ldp_source).not_to receive(:head)
        expect(subject.persisted_size).to eq nil
      end
    end

    describe '#dirty_size' do
      context 'when content has changed from what is currently persisted' do
        context 'and has been set to something that has a #size method (i.e. string or File)' do
          it 'returns the size of the dirty content' do
            dirty_content = double
            allow(dirty_content).to receive(:size) { 8675309 }
            subject.content = dirty_content
            expect(subject.size).to eq dirty_content.size
          end
        end

      end

      context 'when content has not changed from what is currently persisted' do
        it 'returns nil, indicating that the content is not "dirty", but its not necessarily 0 either.' do
          expect(subject.dirty_size).to be_nil
        end
      end
    end

    describe '#size' do
      context 'when content has not changed' do
        it 'returns the value of .persisted_size' do
          expect(subject.size).to eq subject.persisted_size
        end
      end

      context 'when content has changed' do
        it 'returns the value of .dirty_size' do
          subject.content = "i have changed!"
          expect(subject.size).to eq subject.dirty_size
        end
      end

      it 'returns nil when #persisted_size and #dirty_size return nil' do
        allow(subject).to receive(:persisted_size) { nil }
        allow(subject).to receive(:dirty_size) { nil }
        expect(subject.size).to be_nil
      end
    end

    describe ".empty?" do
      it "should not be empty" do
        expect(subject.empty?).to be false
      end
    end

    describe ".has_content?" do
      context "when there's content" do
        before do
          allow(subject).to receive(:size).and_return(10)
        end
        it "should return true" do
          expect(subject.has_content?).to be true
        end
      end

      context "when size is nil" do
        before do
          allow(subject).to receive(:size).and_return(nil)
        end
        it "should not have content" do
          expect(subject).to_not have_content
        end
      end

      context "when content is zero" do
        before do
          allow(subject).to receive(:size).and_return(0)
        end
        it "should return false" do
          expect(subject.has_content?).to be false
        end
      end
    end
  end

  context "when the datastream has local content" do

    before do
      datastream.content = "hi there"
    end

    describe "#inspect" do
      subject { datastream.inspect }
      it { should eq "#<ActiveFedora::Datastream uri=\"http://localhost:8983/fedora/rest/test/1234/abcd\" >" }
    end
  end

  context "original_name" do
    subject { datastream.original_name }

    context "on a new datastream" do
      before { datastream.original_name = "my_image.png" }
      it { should eq "my_image.png" }
    end

    context "when it's saved" do
      let(:parent) { ActiveFedora::Base.create }
      before do
        p = parent
        p.add_file_datastream('one1two2threfour', dsid: 'abcd', mime_type: 'video/webm', original_name: "my_image.png")
        parent.save!
      end

      it "should have original_name" do
        expect(parent.reload.abcd.original_name).to eq 'my_image.png'
      end
    end
  end
end