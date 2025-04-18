require "spec_helper"

describe AbuseReport do
  it { is_expected.to validate_presence_of(:url) }

  context "when report is not spam" do
    context "valid reports" do
      it "is valid" do
        expect(build(:abuse_report)).to be_valid
      end
    end

    context "comment missing" do
      let(:report_without_comment) { build(:abuse_report, comment: nil) }
      it "is invalid" do
        expect(report_without_comment.save).to be_falsey
        expect(report_without_comment.errors[:comment]).not_to be_empty
      end
    end

    context "comment with weird characters" do
      it "is valid with slash and dot" do
        expect(build(:abuse_report, comment: "/.")).to be_valid
      end
      it "is valid in other languages" do
        expect(build(:abuse_report, comment: "café")).to be_valid
      end
      it "is valid in other alphabets" do
        expect(build(:abuse_report, comment: "γεια")).to be_valid
      end
    end

    context "provided email is invalid" do
      BAD_EMAILS.each do |email|
        let(:bad_email) { build(:abuse_report, email: email) }
        it "fails email format check and cannot be created" do
          expect(bad_email.save).to be_falsey
          expect(bad_email.errors[:email]).to include("should look like an email address.")
        end
      end
    end

    context "with a chapter URL that's missing the work id" do
      context "when the chapter exists" do
        let(:work) { create(:work) }
        let(:chapter) { work.chapters.first }
        let(:missing_work_id) { build(:abuse_report, url: "http://archiveofourown.org/chapters/#{chapter.id}/") }

        it "saves and adds the correct work id to the URL" do
          expect(missing_work_id.save).to be_truthy
          expect(missing_work_id.url).to eq("http://archiveofourown.org/works/#{work.id}/chapters/#{chapter.id}/")
        end

        context "when the URL does not include the scheme" do
          let(:missing_work_id) { build(:abuse_report, url: "archiveofourown.org/chapters/#{chapter.id}/") }

          it "saves and adds a scheme and correct work id to the URL" do
            expect(missing_work_id.save).to be_truthy
            expect(missing_work_id.url).to eq("https://archiveofourown.org/works/#{work.id}/chapters/#{chapter.id}/")
          end
        end
      end

      context "when the chapter does not exist" do
        let(:chapter_url) { "http://archiveofourown.org/chapters/000" }
        let(:missing_work_id) { build(:abuse_report, url: chapter_url) }

        it "saves without adding a work id to the URL" do
          expect(missing_work_id.save).to be_truthy
          expect(missing_work_id.url).to eq("#{chapter_url}/")
        end

        context "when the URL does not include the scheme" do
          let(:chapter_url) { "archiveofourown.org/chapters/000" }
          let(:missing_work_id) { build(:abuse_report, url: chapter_url) }

          it "saves and adds a scheme but no work id to the URL" do
            expect(missing_work_id.save).to be_truthy
            expect(missing_work_id.url).to eq("https://#{chapter_url}/")
          end
        end
      end
    end

    context "with a very long URL" do
      let(:long_url) { "https://archiveofourown.org/#{'a' * 2080}" }
      let(:abuse_report) { build(:abuse_report, url: long_url) }

      it "truncates the url to the maximum length" do
        expect(abuse_report.save).to be_truthy
        expect(abuse_report.url).to eq(long_url[0..2079])
      end
    end

    context "invalid url" do
      let(:invalid_url) { build(:abuse_report, url: "nothing before #{ArchiveConfig.APP_URL}") }
      it "text before url" do
        expect(invalid_url.save).to be_falsey
        expect(invalid_url.errors[:url]).not_to be_empty
      end

      let(:not_from_site) { build(:abuse_report, url: "http://www.google.com/not/our/site") }
      it "url not from our site" do
        expect(not_from_site.save).to be_falsey
        expect(not_from_site.errors[:url]).not_to be_empty
      end

      let(:no_url) { build(:abuse_report, url: "") }
      it "no url" do
        expect(no_url.save).to be_falsey
        expect(no_url.errors[:url]).not_to be_empty
      end
    end

    let(:no_email_provided) { build(:abuse_report, email: nil) }
    it "is invalid if an email is not provided" do
      expect(no_email_provided.save).to be_falsey
      expect(no_email_provided.errors[:email]).not_to be_empty
    end

    let(:email_provided) { build(:abuse_report) }
    it "is valid if an email is provided" do
      expect(email_provided.save).to be_truthy
      expect(email_provided.errors[:email]).to be_empty
    end

    context "for an already-reported work" do
      work_url = "http://archiveofourown.org/works/1234"

      let(:common_report) { build(:abuse_report, url: work_url) }
      it "can be submitted up to a set number of times" do
        (ArchiveConfig.ABUSE_REPORTS_PER_WORK_MAX - 1).times do
          create(:abuse_report, url: work_url)
        end
        expect(common_report.save).to be_truthy
        expect(common_report.errors[:base]).to be_empty
      end
    end

    shared_examples "enough already" do |url|
      let(:report) { build(:abuse_report, url: url) }
      it "can't be submitted" do
        expect(report.save).to be_falsey
        expect(report.errors[:base].first).to include("This page has already been reported.")
      end
    end

    shared_examples "alright" do |url|
      let(:report) { build(:abuse_report, url: url) }
      it "can be submitted" do
        expect(report.save).to be_truthy
        expect(report.errors[:base]).to be_empty
      end
    end

    context "for a work reported the maximum number of times" do
      work_url = "http://archiveofourown.org/works/789"

      before do
        ArchiveConfig.ABUSE_REPORTS_PER_WORK_MAX.times do
          create(:abuse_report, url: work_url)
        end
        expect(AbuseReport.count).to eq(ArchiveConfig.ABUSE_REPORTS_PER_WORK_MAX)
      end

      # obviously
      it_behaves_like "enough already", work_url

      # the same work, different protocol
      it_behaves_like "enough already", "https://archiveofourown.org/works/789"

      # the same work, with parameters/anchors
      it_behaves_like "enough already", "http://archiveofourown.org/works/789?smut=yes"
      it_behaves_like "enough already", "http://archiveofourown.org/works/789?smut=yes#timeline"
      it_behaves_like "enough already", "http://archiveofourown.org/works/789#timeline"
      it_behaves_like "enough already", "http://archiveofourown.org/works/789/?smut=yes"
      it_behaves_like "enough already", "http://archiveofourown.org/works/789/#timeline"

      # the same work, in a collection
      it_behaves_like "enough already", "http://archiveofourown.org/collections/rarepair/works/789"

      # the same work, under users
      it_behaves_like "enough already", "http://archiveofourown.org/users/author/works/789"
      it_behaves_like "enough already", "http://archiveofourown.org/users/coauthor/works/789"

      # the same work, subpages
      it_behaves_like "enough already", "http://archiveofourown.org/works/789/bookmarks"
      it_behaves_like "enough already", "http://archiveofourown.org/works/789/collections"
      it_behaves_like "enough already", "http://archiveofourown.org/works/789/comments"
      it_behaves_like "enough already", "http://archiveofourown.org/works/789/kudos"

      # a specific chapter on the work
      it_behaves_like "enough already", "http://archiveofourown.org/works/789/chapters/123"
      it_behaves_like "enough already", "http://archiveofourown.org/works/789/chapters/123#major-character-death"
      it_behaves_like "enough already", "http://archiveofourown.org/works/789/chapters/123?ending=1"
      it_behaves_like "enough already", "http://archiveofourown.org/works/789/chapters/123?ending=2#major-character-death"

      # the same work: variations we don't cover
      it_behaves_like "alright", "http://archiveofourown.org/chapters/123"
      it_behaves_like "alright", "http://archiveofourown.org/comments/show_comments?work_id=789"

      # not the same work
      it_behaves_like "alright", "http://archiveofourown.org/works/9009"
      it_behaves_like "alright", "http://archiveofourown.org/works/78"
      it_behaves_like "alright", "http://archiveofourown.org/works/7890"
      it_behaves_like "alright", "http://archiveofourown.org/external_works/789"

      # unrelated
      it_behaves_like "alright", "http://archiveofourown.org/users/someone"

      context "a month later" do
        before { travel(32.days) }

        it_behaves_like "alright", work_url
      end
    end

    context "for a user profile reported the maximum number of times" do
      user_url = "http://archiveofourown.org/users/someone"

      before do
        ArchiveConfig.ABUSE_REPORTS_PER_USER_MAX.times do
          create(:abuse_report, url: user_url)
        end
        expect(AbuseReport.count).to eq(ArchiveConfig.ABUSE_REPORTS_PER_USER_MAX)
      end

      # obviously
      it_behaves_like "enough already", user_url

      # the same user, different protocol
      it_behaves_like "enough already", "https://archiveofourown.org/users/someone"

      # the same user, with parameters/anchors
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone?sfw=yes"
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone?sfw=yes#timeline"
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone#timeline"
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone/?sfw=yes"
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone/#timeline"

      # the same user, as admin (why admin?)
      it_behaves_like "enough already", "http://archiveofourown.org/admin/users/someone"

      # the same user, subpages
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone/bookmarks"
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone/claims"
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone/pseuds/"
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone/pseuds/ghostwriter"
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone/pseuds/g h o s t w r i t e r"

      # the same user, Unicode in parameters
      it_behaves_like "enough already", "http://archiveofourown.org/users/someone/inbox?utf8=✓&filters[read]=false"

      # not the same user
      it_behaves_like "alright", "http://archiveofourown.org/users/some"
      it_behaves_like "alright", "http://archiveofourown.org/users/someoneelse"
      it_behaves_like "alright", "http://archiveofourown.org/users/somebody"

      # unrelated
      it_behaves_like "alright", "http://archiveofourown.org/works/789"

      context "a month later" do
        before { travel(32.days) }

        it_behaves_like "alright", user_url
      end
    end

    context "for a URL that is not a work" do
      page_url = "http://archiveofourown.org/tags/Testing/works"

      let(:common_report) { build(:abuse_report, url: page_url) }
      it "can be submitted an unrestricted number of times" do
        ArchiveConfig.ABUSE_REPORTS_PER_WORK_MAX.times do
          create(:abuse_report, url: page_url)
        end
        expect(common_report.save).to be_truthy
        expect(common_report.errors[:base]).to be_empty
      end
    end

    context "for alternate URL format" do
      let(:report) { build(:abuse_report) }

      it "no protocol" do
        report.url = "archiveofourown.org"
        expect(report.valid?).to be_truthy
      end

      it "dot com" do
        report.url = "http://archiveofourown.com"
        expect(report.valid?).to be_truthy
      end

      it "acronym" do
        report.url = "http://ao3.org"
        expect(report.valid?).to be_truthy
      end
    end

    context "when email is valid" do
      let(:report) { build(:abuse_report, email: "email@example.com") }

      context "when email has submitted less than the maximum daily number of reports" do
        before do
          (ArchiveConfig.ABUSE_REPORTS_PER_EMAIL_MAX - 1).times do
            create(:abuse_report, email: "email@example.com")
          end
        end

        it "can be submitted" do
          expect(report.save).to be_truthy
          expect(report.errors[:base]).to be_empty
        end
      end

      context "when email has submitted the maximum daily number of reports" do
        before do
          ArchiveConfig.ABUSE_REPORTS_PER_EMAIL_MAX.times do
            create(:abuse_report, email: "email@example.com")
          end
        end

        it "can't be submitted" do
          expect(report.save).to be_falsey
          expect(report.errors[:base].first).to include("daily reporting limit")
        end

        context "when it's a day later" do
          before { travel(1.day) }

          it "can be submitted" do
            expect(report.save).to be_truthy
            expect(report.errors[:base]).to be_empty
          end
        end
      end
    end
  end

  context "when report is spam" do
    let(:legit_user) { create(:user) }
    let(:spam_report) { build(:abuse_report, username: "viagra-test-123") }
    let!(:safe_report) { build(:abuse_report, username: "viagra-test-123", email: legit_user.email) }

    before do
      allow(Akismetor).to receive(:spam?).and_return(true)
    end

    it "is not valid if Akismet flags it as spam" do
      expect(spam_report.save).to be_falsey
      expect(spam_report.errors[:base]).to include("This report looks like spam to our system!")
    end

    it "is valid even if the email casing is different" do
      legit_user.email = legit_user.email.upcase
      legit_user.save
      User.current_user = legit_user
      expect(safe_report.save).to be_truthy
    end

    it "is valid even with spam if logged in and providing correct email" do
      User.current_user = legit_user
      expect(safe_report.save).to be_truthy
    end
  end

  context "when report is submitted to Akismet" do
    let(:report) { build(:abuse_report) }

    it "has comment_type \"contact-form\"" do
      expect(report.akismet_attributes[:comment_type]).to eq("contact-form")
    end

    it "has user_role \"user-with-nonmatching-email\" when reporter is logged in" do
      User.current_user = create(:user)
      expect(report.akismet_attributes[:user_role]).to eq("user-with-nonmatching-email")
    end

    it "has user_role \"guest\" when reporter is logged out" do
      expect(report.akismet_attributes[:user_role]).to eq("guest")
    end
  end

  describe "#attach_work_download" do
    include ActiveJob::TestHelper

    let(:ticket_id) { "123" }
    let(:work) { create(:work) }

    it "does not attach a download for non-work URLs asynchronously" do
      allow(subject).to receive(:url).and_return("http://archiveofourown.org/users/someone/")

      expect { subject.attach_work_download(ticket_id) }
        .not_to have_enqueued_job
    end

    it "does not attach a download for comment sub-URLs asynchronously" do
      allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/comments/")

      expect { subject.attach_work_download(ticket_id) }
        .not_to have_enqueued_job
    end

    it "attaches a download for work URLs asynchronously" do
      allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/")

      expect { subject.attach_work_download(ticket_id) }
        .to have_enqueued_job
    end
  end

  describe "#creator_ids" do
    it "returns no creator ids for non-work URLs" do
      allow(subject).to receive(:url).and_return("http://archiveofourown.org/users/someone/")

      expect(subject.creator_ids).to be_nil
    end

    it "returns no creator ids for comment sub-URLs" do
      allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/123/comments/")

      expect(subject.creator_ids).to be_nil
    end

    context "for work URLs" do
      it "returns deletedwork for a work that doesn't exist" do
        allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/000/")

        expect(subject.creator_ids).to eq("deletedwork")
      end

      context "for a single creator" do
        let(:work) { create(:work) }

        it "returns a single creator id" do
          allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/")

          expect(subject.creator_ids).to eq(work.users.first.id.to_s)
        end
      end

      context "for an anonymous work" do
        let(:anonymous_collection) { create(:anonymous_collection) }
        let(:work) { create(:work, collections: [anonymous_collection]) }

        it "returns a single creator id" do
          allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/")

          expect(subject.creator_ids).to eq(work.users.first.id.to_s)
        end
      end

      context "for an unrevealed work" do
        let(:unrevealed_collection) { create(:unrevealed_collection) }
        let(:work) { create(:work, collections: [unrevealed_collection]) }

        it "returns a single creator id" do
          allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/")

          expect(subject.creator_ids).to eq(work.users.first.id.to_s)
        end
      end

      context "for multiple pseuds of one creator" do
        let(:user) { create(:user) }
        let(:pseud) { create(:pseud, user: user) }
        let(:work) { create(:work, authors: [pseud, user.default_pseud]) }

        it "returns a single creator id" do
          allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/")

          expect(subject.creator_ids).to eq(user.id.to_s)
        end
      end

      context "for multiple creators" do
        let(:user1) { create(:user, id: 10) }
        let(:user2) { create(:user, id: 11) }
        let(:work) { create(:work, authors: [user2.default_pseud, user1.default_pseud]) }

        it "returns a sorted list of creator ids" do
          allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/")

          expect(subject.creator_ids).to eq("#{user1.id}, #{user2.id}")
        end
      end

      context "for an invited co-creator that hasn't accepted yet" do
        let(:user) { create(:user) }
        let(:invited) { create(:user) }
        let(:work) { create(:work, authors: [user.default_pseud, invited.default_pseud]) }
        let(:creatorship) { work.creatorships.last }

        before do
          creatorship.approved = false
          creatorship.save!(validate: false)
        end

        it "returns only the creator" do
          allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/")

          expect(subject.creator_ids).to eq(user.id.to_s)
        end
      end
    end

    context "for an orphaned work" do
      let!(:orphan_account) { create(:user, login: "orphan_account") }
      let(:orphaneer) { create(:user, id: 20) }
      let(:work) { create(:work, authors: [orphaneer.default_pseud]) }

      context "recently orphaned" do
        before do
          Creatorship.orphan([orphaneer.default_pseud], [work], false)
        end

        it "returns orphanedwork and the original creator" do
          allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/")

          expect(subject.creator_ids).to eq("orphanedwork, #{orphaneer.id}")
        end
      end

      context "orphaned a long time ago" do
        before do
          Creatorship.orphan([orphaneer.default_pseud], [work], false)
          work.original_creators.destroy_all
        end

        it "returns orphanedwork" do
          allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/")

          expect(subject.creator_ids).to eq("orphanedwork")
        end
      end

      context "partially orphaned" do
        let(:cocreator) { create(:user, id: 21) }
        let(:work) { create(:work, authors: [cocreator.default_pseud, orphaneer.default_pseud]) }

        before do
          Creatorship.orphan([orphaneer.default_pseud], [work], false)
        end

        it "returns a sorted list of orphanedwork, the co-creator and the original creator" do
          allow(subject).to receive(:url).and_return("http://archiveofourown.org/works/#{work.id}/")

          expect(subject.creator_ids).to eq("orphanedwork, #{orphaneer.id}, #{cocreator.id}")
        end
      end
    end
  end
end
