module RepositoryManager
  module ActsAsRepository
    extend ActiveSupport::Concern

    included do
    end

    module ClassMethods
      def acts_as_repository(options = {})

        has_many :shares, :through => :shares_items, dependent: :destroy
        has_many :shares_items, as: :item, dependent: :destroy
        has_many :shares_owners, as: :owner, :class_name => 'Share'

        has_many :repositories, as: :owner #, dependent: :destroy

        #cattr_accessor :yaffle_text_field
        #self.yaffle_text_field = (options[:yaffle_text_field] || :last_squawk).to_s
        # your code will go here

        include RepositoryManager::ActsAsRepository::LocalInstanceMethods
      end
    end

    module LocalInstanceMethods
      #Share the repository to the items, with the repo_permissions
      #share_permission contains :
      #can_add and can_remove specify if the users can add/remove people to the share
      def share(repository, items, repo_permissions = nil, share_permissions = nil)
        authorisations = get_authorisations(repository)

        #Here we look if the instance has the authorisation for making a share
        if can_share(nil, authorisations)

          repo_permissions = make_repo_permissions(repo_permissions, authorisations)

          share = Share.new(repo_permissions)
          share.owner = self

          repository.shares << share
          if items.kind_of?(Array)
            #add each item to this share
            items.each do |i|
              shareItem = SharesItem.new(share_permissions)
              shareItem.item = i
              #add the shares items in the share
              share.shares_items << shareItem
            end
          else
            shareItem = SharesItem.new(share_permissions)
            shareItem.item = items
            #add the shares items in the share
            share.shares_items << shareItem
          end


          repository.save
        else
          # No permission => No share
          false
        end
      end

      #Create a folder with the name (name) in the directory (sourceFolder)
      #Return the object of the folder created if it is ok
      #Return false if the folder is not created (no authorisation)
      def createFolder(name, sourceFolder = nil)
        #If he want to create a folder in a directory, we have to check if he have the authorisation
        if can_create(sourceFolder)

          folder = Folder.new(name: name)
          folder.owner = self
          folder.save

          #If we want to create a folder in a folder, we have to check if we have the authorisation
          if sourceFolder
            #authorisations = get_authorisations(sourceFolder)
            sourceFolder.addRepository(folder)
          end

          return folder
        else
          return false
        end
      end

      def deleteRepository(repository)
        if can_delete(repository)
          repository.destroy!
        end
      end

      #Create the file (file) in the directory (sourceFolder)
      #param file can be a ile, or a instance of AppFile
      #param file can be a File, or a instance of AppFile
      #Return the object of the file created if it is ok
      #Return false if the file is not created (no authorisation)
      def createFile(file, sourceFolder = nil)
        #If he want to create a file in a directory, we have to check if he have the authorisation
        if can_create(sourceFolder)
          if file.class.name == 'File'
            appFile = AppFile.new
            appFile.name = file
            appFile.owner = self
            appFile.save!
          elsif file.class.name == 'AppFile'
            appFile = file
            appFile.owner = self
            appFile.save!
          else
            return false
          end

          #If we want to create a folder in a folder, we have to check if we have the authorisation
          if sourceFolder
            #authorisations = get_authorisations(sourceFolder)
            sourceFolder.addRepository(file)
          end

          return appFile
        else
          return false
        end
      end

      #Return false if the entity has not the authorisation to share this rep
      #Return true if the entity can share this rep with all the authorisations
      #Return an Array if the entity can share but with restriction
      #Return true if the repository is nil (he as all authorisations on his own rep)
      def get_authorisations(repository=nil)
        #If repository is nil, he can do what he want
        return true if repository==nil

        # If the item is the owner, he can share !
        if repository.owner == self
          #You can do what ever you want :)
          return true
          #Find if a share of this rep exist for the self instance
        elsif s = self.shares.where(repository_id: repository.id).take
          #Ok, give an array with the permission of the actual share
          # (we can't share with more permission then we have)
          return {can_share: s.can_share, can_read: s.can_read, can_create: s.can_create, can_update: s.can_update, can_delete: s.can_delete}
        else
          #We look at the ancestor if there is a share
          ancestor_ids = repository.ancestor_ids
          #check the nearest share if it exist
          if s = self.shares.where(repository_id: ancestor_ids).last
            return {can_share: s.can_share, can_read: s.can_read, can_create: s.can_create, can_update: s.can_update, can_delete: s.can_delete}
          end
        end
        #else, false
        return false
      end

      #Return true if you can share the repo, else false
      #You can give the authorisations or the repository as params
      def can_share(repository, authorisations = nil)
        can_do('share', repository, authorisations)
      end

      #Return true if you can create in the repo, false else
      def can_create(repository, authorisations = nil)
        can_do('create', repository, authorisations)
      end

      #Return true if you can edit the repo, false else
      def can_update(repository, authorisations = nil)
        can_do('update', repository, authorisations)
      end

      #Return true if you can delete the repo, false else
      def can_delete(repository, authorisations = nil)
        can_do('delete', repository, authorisations)
      end

      private

      #Return if you can do or not this action (what)
      def can_do(what, repository, authorisations = nil)
        #If we pass no authorisations we have to get it
        if authorisations === nil
          authorisations = get_authorisations(repository)
        end

        case what
          when 'read'
            authorisations == true || (authorisations.kind_of?(Hash) && authorisations[:can_read] == true)
          when 'delete'
            authorisations == true || (authorisations.kind_of?(Hash) && authorisations[:can_delete] == true)
          when 'update'
            authorisations == true || (authorisations.kind_of?(Hash) && authorisations[:can_update] == true)
          when 'share'
            authorisations == true || (authorisations.kind_of?(Hash) && authorisations[:can_share] == true)
          when 'create'
            authorisations == true || (authorisations.kind_of?(Hash) && authorisations[:can_create] == true)
          else
            false
        end

      end

      #Correct the repo_permissions with the authorisations
      def make_repo_permissions(wanted_permissions, authorisations)
        #If it is an array, we have restriction in the permissions
        if authorisations.kind_of?(Hash) && wanted_permissions
          #built the share with the accepted permissions
          #We remove the permission if we can't share it
          if wanted_permissions[:can_read] == true && authorisations[:can_read] == false
            wanted_permissions[:can_read] = false
          end
          if wanted_permissions[:can_create] == true && authorisations[:can_create] == false
            wanted_permissions[:can_create] = false
          end
          if wanted_permissions[:can_update] == true && authorisations[:can_update] == false
            wanted_permissions[:can_update] = false
          end
          if wanted_permissions[:can_delete] == true && authorisations[:can_delete] == false
            wanted_permissions[:can_delete] = false
          end
        end
        return wanted_permissions
      end

    end
  end
end

ActiveRecord::Base.send :include, RepositoryManager::ActsAsRepository